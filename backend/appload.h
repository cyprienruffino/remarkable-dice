// Minimal client for AppLoad's backend protocol: https://github.com/asivery/rm-appload
//
// AppLoad starts the backend with the path of a SOCK_SEQPACKET socket as its
// first argument. Each message is a packet holding {int type, int length},
// followed by a packet holding the UTF-8 contents. AppLoad always sends the
// contents packet, but only reads it from the backend when it isn't empty.
#ifndef APPLOAD_H
#define APPLOAD_H

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace appload {

// System messages, sent by AppLoad itself
constexpr int MSG_TERMINATE = -1;     // the app is closing, exit
constexpr int MSG_NEW_FRONTEND = -2;  // a frontend connected; contents: number of frontends
constexpr int MSG_LOST_FRONTEND = -3; // a frontend went away; contents: number of frontends

constexpr size_t MAX_MESSAGE_LENGTH = 10485760;

struct Message
{
    int type;
    std::string contents;
};

class Connection
{
public:
    ~Connection()
    {
        if (m_fd != -1) {
            close(m_fd);
        }
    }

    bool connect(const char *socketPath)
    {
        m_fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
        if (m_fd == -1) {
            return false;
        }
        sockaddr_un address = {};
        address.sun_family = AF_UNIX;
        std::strncpy(address.sun_path, socketPath, sizeof address.sun_path - 1);
        return ::connect(m_fd, reinterpret_cast<sockaddr *>(&address), sizeof address) == 0;
    }

    // For poll()ing alongside other file descriptors
    int fd() const { return m_fd; }

    bool send(int type, const std::string &contents)
    {
        const Header header = { type, int(contents.size()) };
        if (::send(m_fd, &header, sizeof header, 0) == -1) {
            return false;
        }
        return contents.empty() || ::send(m_fd, contents.data(), contents.size(), 0) != -1;
    }

    // Blocks until a message arrives, returns false once AppLoad hangs up
    bool receive(Message *message)
    {
        Header header;
        if (recv(m_fd, &header, sizeof header, 0) < ssize_t(sizeof header)) {
            return false;
        }
        if (header.length < 0 || size_t(header.length) > MAX_MESSAGE_LENGTH) {
            return false;
        }
        m_buffer.resize(std::max<size_t>(header.length, 1));
        // AppLoad always sends the contents packet, even when empty
        const ssize_t received = recv(m_fd, m_buffer.data(), header.length, 0);
        if (received < 0) {
            return false;
        }
        message->type = header.type;
        message->contents.assign(m_buffer.data(), received);
        return true;
    }

private:
    struct Header
    {
        int type;
        int length;
    };

    int m_fd = -1;
    std::vector<char> m_buffer;
};

} // namespace appload

#endif // APPLOAD_H
