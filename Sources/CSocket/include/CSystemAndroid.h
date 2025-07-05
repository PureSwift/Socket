
#ifdef __BIONIC__

#include <sys/socket.h>
#include <sys/sysinfo.h>
#include <sys/timerfd.h>
#include <sys/types.h>
#include <errno.h>

extern int android_fcntl(int fd, int cmd);
extern int android_fcntl_value(int fd, int cmd, int value);
extern int android_fcntl_ptr(int fd, int cmd, void* ptr);

extern int android_ioctl(int fd, unsigned long op);
extern int android_ioctl_value(int fd, unsigned long op, int value);
extern int android_ioctl_ptr(int fd, unsigned long op, void* ptr);

#endif
