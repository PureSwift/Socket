//
//  android.c
//  Socket
//
//  Created by Alsey Coleman Miller on 7/5/25.
//

#ifdef __ANDROID__

#include "CSystemAndroid.h"
#include <sys/socket.h>
#include <sys/sysinfo.h>
#include <sys/timerfd.h>
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/ioctl.h>

extern int android_fcntl(int fd, int cmd)
{
    return fcntl(fd, cmd);
}

extern int android_fcntl_value(int fd, int cmd, int value)
{
    return fcntl(fd, cmd, value);
}

extern int android_fcntl_ptr(int fd, int cmd, void* ptr)
{
    return fcntl(fd, cmd, ptr);
}

extern int android_ioctl(int fd, unsigned long op)
{
    return ioctl(fd, op);
}

extern int android_ioctl_value(int fd, unsigned long op, int value)
{
    return ioctl(fd, op, value);
}

extern int android_ioctl_ptr(int fd, unsigned long op, void* ptr)
{
    return ioctl(fd, op, ptr);
}

#endif
