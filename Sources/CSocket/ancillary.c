//
//  ancillary.c
//  Socket
//
//  SCM_RIGHTS file descriptor passing. See CSocketAncillary.h.
//

#include "CSocketAncillary.h"

#if defined(__linux__) || defined(__ANDROID__) || defined(__APPLE__)

#include <string.h>
#include <errno.h>
#include <unistd.h>

ssize_t c_socket_send_descriptors(int socket,
                                  const void *buffer,
                                  size_t length,
                                  const int *descriptors,
                                  size_t count,
                                  int flags)
{
    if (count > C_SOCKET_MAX_DESCRIPTORS) {
        errno = EINVAL;
        return -1;
    }

    // A message with no payload may be dropped before its ancillary data is seen, so the
    // caller must always send at least one byte alongside the descriptors.
    if (length == 0) {
        errno = EINVAL;
        return -1;
    }

    struct iovec iov;
    iov.iov_base = (void *)buffer;
    iov.iov_len = length;

    struct msghdr message;
    memset(&message, 0, sizeof(message));
    message.msg_iov = &iov;
    message.msg_iovlen = 1;

    // Sized for the worst case so the buffer is a fixed, stack allocated size.
    char control[CMSG_SPACE(sizeof(int) * C_SOCKET_MAX_DESCRIPTORS)];

    if (count > 0) {

        memset(control, 0, sizeof(control));

        message.msg_control = control;
        message.msg_controllen = CMSG_SPACE(sizeof(int) * count);

        struct cmsghdr *header = CMSG_FIRSTHDR(&message);
        header->cmsg_level = SOL_SOCKET;
        header->cmsg_type = SCM_RIGHTS;
        header->cmsg_len = CMSG_LEN(sizeof(int) * count);

        memcpy(CMSG_DATA(header), descriptors, sizeof(int) * count);

        // msg_controllen must match what was actually written.
        message.msg_controllen = header->cmsg_len;
    }

    return sendmsg(socket, &message, flags);
}

ssize_t c_socket_receive_descriptors(int socket,
                                     void *buffer,
                                     size_t length,
                                     int *descriptors,
                                     size_t capacity,
                                     size_t *received_count,
                                     int *truncated,
                                     int flags)
{
    *received_count = 0;
    *truncated = 0;

    struct iovec iov;
    iov.iov_base = buffer;
    iov.iov_len = length;

    char control[CMSG_SPACE(sizeof(int) * C_SOCKET_MAX_DESCRIPTORS)];
    memset(control, 0, sizeof(control));

    struct msghdr message;
    memset(&message, 0, sizeof(message));
    message.msg_iov = &iov;
    message.msg_iovlen = 1;
    message.msg_control = control;
    message.msg_controllen = sizeof(control);

    ssize_t result = recvmsg(socket, &message, flags);

    if (result < 0) {
        return result;
    }

    // The kernel had more ancillary data than fitted; any descriptors it did deliver are still
    // handled below, and the caller is told the set is incomplete.
    if (message.msg_flags & MSG_CTRUNC) {
        *truncated = 1;
    }

    for (struct cmsghdr *header = CMSG_FIRSTHDR(&message);
         header != NULL;
         header = CMSG_NXTHDR(&message, header)) {

        if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_RIGHTS) {
            continue;
        }

        size_t payload = header->cmsg_len - CMSG_LEN(0);
        size_t available = payload / sizeof(int);

        const int *incoming = (const int *)(const void *)CMSG_DATA(header);

        for (size_t index = 0; index < available; index++) {

            if (descriptors != NULL && *received_count < capacity) {
                descriptors[*received_count] = incoming[index];
                (*received_count)++;
            } else {
                // Close rather than leak a descriptor the caller cannot accept.
                close(incoming[index]);
                *truncated = 1;
            }
        }
    }

    return result;
}

#endif
