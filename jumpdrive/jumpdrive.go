package main

import (
	"bytes"
	"errors"
	"fmt"
	"image/png"
	"io"
	"log"
	"os"
	"os/exec"
	"strings"

	"github.com/u-root/u-root/pkg/checker"
	"github.com/u-root/u-root/pkg/fb"
	"github.com/u-root/u-root/pkg/kmodule"
	"github.com/vishvananda/netlink"
)

const (
	// IFace is default usb networking interface
	IFaceName = "usb0"
	// IPAddress is default IP address for USB tethering
	IPAddress = "10.0.0.100/24"
	// CPUCount is a number of CPU Core available for this device
	CpuCount = 4
	// SplashscreenFile is a filepath to splash file to display
	SplashscreenFile = "/usr/splash.png"
)

var (
	// KernelModules is a list of kernel module to load
	KernelModules = []string{
		"sunxi",
		"libcomposite",
		"usb_f_ecm", // ethernet-over-usb
		"usb_f_acm",
		"usb_f_ncm",
		"goodix_ts", // touchscreen
	}
	// StorageDevices is a list of devices to attach as mass storage
	StorageDevices = []string{
		"/dev/mmcblk0", // eMMC
		"/dev/mmcblk2", // SDCard
	}
)

func initNetwork() error {
	usb, err := netlink.LinkByName(IFaceName)
	if err != nil {
		return fmt.Errorf("failed to get %s link: %w", IFaceName, err)
	}
	addr, _ := netlink.ParseAddr(IPAddress)
	if err := netlink.AddrAdd(usb, addr); err != nil {
		return fmt.Errorf("failed to assign IP address %s to %s: %w", IPAddress, IFaceName, err)
	}
	if err := netlink.LinkSetUp(usb); err != nil {
		return fmt.Errorf("failed to enable %s interface link: %w", IFaceName, err)
	}
	return nil
}

func stringFromDict(m map[string]string) string {
	b := new(bytes.Buffer)
	for key, value := range m {
		fmt.Fprintf(b, "%s=%s ", key, value)
	}
	return b.String()
}

func initGadget() error {
	for _, module := range KernelModules {
		log.Printf("Loading kernel module %v", module)
		if err := kmodule.Probe(module, ""); err != nil {
			return fmt.Errorf("could not load %s module: %w", module, err)
		}
	}

	gMultiOptions := map[string]string{
		"file":          strings.Join(StorageDevices, ","),
		"iManufacturer": "Pine64",
		"iProduct":      "Pinephone",
		"iSerialNumber": "0123456789",
		"idVendor":      "0x1209",
		"idProduct":     "0x4201",
	}

	gMultiOptionsStr := stringFromDict(gMultiOptions)
	log.Printf("modprobe g_multi %s", gMultiOptionsStr)
	if err := kmodule.Probe("g_multi", gMultiOptionsStr); err != nil {
		return fmt.Errorf("could not load g_multi module with option %s: %w", gMultiOptionsStr, err)
	}

	return nil
}

func setupPowersaving(cpuCount int) (errors []error) {
	for i := 0; i <= cpuCount-1; i++ {
		scalingGovFilepath := fmt.Sprintf("/sys/devices/system/cpu/cpu%d/cpufreq/scaling_governor", i)
		scalingGovWriter, err := os.OpenFile(scalingGovFilepath, os.O_WRONLY, 0o644)
		if err != nil {
			errors = append(errors, fmt.Errorf("failed open %s file: %s", scalingGovFilepath, err))
			continue
		}
		powersavingStrReader := strings.NewReader("powersave")
		// os.WriteFile fails with "invalid argument" error
		// On write(2), sysfs expects the entire buffer to be passed during the first write.
		// Sysfs then passes the entire buffer to the store() method.
		// https://www.kernel.org/doc/html/latest/filesystems/sysfs.html#reading-writing-attribute-data
		if _, err := io.Copy(scalingGovWriter, powersavingStrReader); err != nil {
			errors = append(errors, fmt.Errorf("failed to set powersaving scaling for cpu%d: %w", i, err))
		}
	}
	return errors
}

func checkInterface(ifname string) error {
	checklist := []checker.Check{
		{
			Name:        fmt.Sprintf("%s exists", ifname),
			Run:         checker.InterfaceExists(ifname),
			Remediate:   nil,
			StopOnError: true,
		},
		{
			Name:        fmt.Sprintf("%s has global addresses", ifname),
			Run:         checker.InterfaceHasGlobalAddresses(ifname),
			Remediate:   nil,
			StopOnError: true,
		},
	}

	return checker.Run(checklist)
}

func displaySplashscreen(pngFile string) error {
	if err := os.WriteFile("/sys/class/graphics/fbcon/cursor_blink", []byte("0"), 0644); err != nil {
		return errors.New("failed to disable framebuffer cursor")
	}

	imageFile, _ := os.Open(pngFile)
	defer imageFile.Close()

	img, err := png.Decode(imageFile)
	if err != nil {
		return fmt.Errorf("invalid splash screen image: %w", err)
	}

	if err = fb.DrawImageAt(img, 0, 0); err != nil {
		return fmt.Errorf("failed to draw splash screen: %w", err)
	}

	return nil
}

func startSSH() error {
	cmd := exec.Command("sshd")
	cmd.Dir = "/etc/ssh"
	if err := cmd.Start(); err != nil {
		return err
	}
	log.Printf("[%d] sshd is running...", cmd.Process.Pid)
	err := cmd.Wait()
	return err
}

func main() {
	log.Print("Jumpdrive initializing...")
	if err := initGadget(); err != nil {
		log.Printf("failed to init USB gadget: %v\n", err)
	}

	if err := initNetwork(); err != nil {
		log.Printf("failed to init network: %v\n", err)
	}

	if err := checkInterface(IFaceName); err != nil {
		if err := checker.EmergencyShell("Failed to start Jumpdrive")(); err != nil {
			log.Print(err)
		}
	}

	if errs := setupPowersaving(CpuCount); len(errs) > 0 {
		for _, err := range errs {
			log.Print(err)
		}
	}

	if err := displaySplashscreen(SplashscreenFile); err != nil {
		log.Printf("failed to display splashscreen: %v", err)
	}

	if err := startSSH(); err != nil {
		log.Printf("sshd exited with an error: %v", err)
	}
}
