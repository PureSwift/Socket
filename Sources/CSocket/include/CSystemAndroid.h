
#ifdef __ANDROID__

#include <sys/socket.h>
#include <sys/types.h>

int android_fcntl(int fd, int cmd);
int android_fcntl_value(int fd, int cmd, int value);
int android_fcntl_ptr(int fd, int cmd, void* ptr);

int android_ioctl(int fd, unsigned long op);
int android_ioctl_value(int fd, unsigned long op, int value);
int android_ioctl_ptr(int fd, unsigned long op, void* ptr);

#endif
