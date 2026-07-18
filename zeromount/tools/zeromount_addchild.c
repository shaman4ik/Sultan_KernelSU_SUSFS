// zeromount_addchild.c — force a real-but-debloated dirent back into readdir.
//
// Companion to the "61_" kernel change (ZEROMOUNT_IOC_ADD_DIR_CHILD). Registers
// {directory, child_name, d_type} into ZeroMount's inject table so that a child
// which still resolves by name (ext4 htree lookup intact) but was cut from the
// directory's linear listing reappears in getdents — without touching the mount
// or the on-disk image. PMS then enumerates it and open()s it by name, which
// resolves the real inode, so it is scanned as a trusted package.
//
// Build (arm64, from an NDK toolchain):
//   aarch64-linux-android<API>-clang -O2 -static -o zeromount_addchild zeromount_addchild.c
// Run as root (needs CAP_SYS_ADMIN — same as every other ZeroMount ioctl):
//   ./zeromount_addchild /product/overlay NavigationBarModeGestural --dir
//
// Register the CANONICAL path PMS enumerates (/product/overlay), and the REAL
// child name (so name resolution hits the real inode). Default type is --dir.
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/ioctl.h>

#define ZEROMOUNT_IOC_MAGIC 0x5A
#define ZM_FLAG_IS_DIR      (1u << 7)

/* Must match the kernel struct byte-for-byte (arm64: two 8-byte ptrs + u32). */
struct zeromount_ioctl_data {
	const char *virtual_path;  /* directory, e.g. "/product/overlay" */
	const char *real_path;     /* bare child name, e.g. "NavigationBarModeGestural" */
	unsigned int flags;        /* ZM_FLAG_IS_DIR for a directory child */
};

#define ZEROMOUNT_IOC_ADD_DIR_CHILD \
	_IOW(ZEROMOUNT_IOC_MAGIC, 12, struct zeromount_ioctl_data)

int main(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr,
			"usage: %s <dir> <child_name> [--dir|--file]\n"
			"  e.g. %s /product/overlay NavigationBarModeGestural --dir\n",
			argv[0], argv[0]);
		return 2;
	}

	struct zeromount_ioctl_data d;
	d.virtual_path = argv[1];
	d.real_path    = argv[2];
	d.flags = ZM_FLAG_IS_DIR; /* default: directory child */
	if (argc >= 4 && strcmp(argv[3], "--file") == 0)
		d.flags = 0;

	int fd = open("/dev/zeromount", O_RDWR);
	if (fd < 0) {
		perror("open /dev/zeromount");
		return 1;
	}
	if (ioctl(fd, ZEROMOUNT_IOC_ADD_DIR_CHILD, &d) < 0) {
		perror("ioctl ADD_DIR_CHILD");
		close(fd);
		return 1;
	}
	close(fd);
	printf("registered %s/%s (%s)\n", argv[1], argv[2],
	       (d.flags & ZM_FLAG_IS_DIR) ? "dir" : "file");
	return 0;
}
