//
//  CSocketAncillary.h
//  Socket
//
//  Passing file descriptors over a Unix domain socket with SCM_RIGHTS.
//
//  The CMSG_* accessors are C macros and so cannot be called from Swift. Rather than
//  reimplement their alignment arithmetic, these shims perform the whole exchange in C.
//

#ifndef CSocketAncillary_h
#define CSocketAncillary_h

#if defined(__linux__) || defined(__ANDROID__) || defined(__APPLE__)

#include <sys/types.h>
#include <sys/socket.h>
#include <stddef.h>

/// Send a message carrying file descriptors as SCM_RIGHTS ancillary data.
///
/// @param socket       The socket to send on. Must be a Unix domain socket.
/// @param buffer       The message payload. At least one byte must be sent, because a message
///                     with no payload may be discarded before its ancillary data is delivered.
/// @param length       The payload length in bytes.
/// @param descriptors  The descriptors to send, or NULL when sending none.
/// @param count        How many descriptors to send.
/// @param flags        Flags for sendmsg().
/// @return The number of payload bytes sent, or -1 with errno set.
ssize_t c_socket_send_descriptors(int socket,
                                  const void *buffer,
                                  size_t length,
                                  const int *descriptors,
                                  size_t count,
                                  int flags);

/// Receive a message and any SCM_RIGHTS file descriptors that accompany it.
///
/// Descriptors beyond `capacity` are closed rather than leaked, and `truncated` reports it.
///
/// @param socket         The socket to receive from.
/// @param buffer         Where to write the payload.
/// @param length         The capacity of `buffer` in bytes.
/// @param descriptors    Where to write received descriptors, or NULL to accept none.
/// @param capacity       How many descriptors `descriptors` can hold.
/// @param received_count Set to the number of descriptors written. Must not be NULL.
/// @param truncated      Set to 1 if descriptors had to be discarded. Must not be NULL.
/// @param flags          Flags for recvmsg().
/// @return The number of payload bytes received, 0 at end of stream, or -1 with errno set.
ssize_t c_socket_receive_descriptors(int socket,
                                     void *buffer,
                                     size_t length,
                                     int *descriptors,
                                     size_t capacity,
                                     size_t *received_count,
                                     int *truncated,
                                     int flags);

/// The maximum number of descriptors a single message may carry.
///
/// Matches the kernel's SCM_MAX_FD, and bounds the ancillary buffer these shims allocate.
#define C_SOCKET_MAX_DESCRIPTORS 253

#endif

#endif /* CSocketAncillary_h */
