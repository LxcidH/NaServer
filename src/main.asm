global _start

section .bss
    socket_fd: resq 1
    accept_fd: resq 1
    buffer: resq 100
    FILENAME_START: resq 1 ; (8 bytes)
    FILENAME_END: resq 1 ; (8 bytes)
    file_buffer: resb 4096  ; (4KB)
section .data
    delimiter: db ' '
    index_html_str: db "index.html", 0

    http_response:
        ; Status line
        db "HTTP/1.1 200 OK", 0x0D, 0x0A

        ; Headers
        db "Content-Type: text/html", 0x0D, 0x0A
        db "Connection: close", 0x0D, 0x0A

        ; The blank line
        db 0x0D, 0x0A
    http_response_len equ $-http_response
    
    ; The sockaddr_in struct (16 bytes)
    pop_sa:
        dw 2            ; sin_family: AF_INET (2 bytes) -> 0x0002
                        ; (x86 stores this as 02 00, which is fine for local constants)
        
        db 0x1F, 0x91   ; sin_port: port 8080 (2 bytes)
                        ; We write the high byte (1F), then the low byte (90)
                        ; so memory is [1F][90] (big endian)

        dd 0            ; sin_addr: 0.0.0.0 (4 bytes) -> 0x00000000

        dq 0            ; sin_zero: padding (8 bytes) -> all zeros

section .text
_start:
    ; SYS_SOCKET - create the endpoint
    mov rax, 41
    mov rdi, 2          ; AF_INET
    mov rsi, 1          ; SOCK_STREAM
    mov rdx, 0
    syscall

    ; Check if RAX is valid, if so,
    ; Save the file descriptor
    cmp rax, 0
    jl handle_error

    mov [socket_fd], rax


    ; SYS_BIND - Assign an address
    mov rax, 49
    mov rdi, [socket_fd]
    mov rsi, pop_sa
    mov rdx, 16         ; struct size in bytes
    syscall

    ; Check for bind errors
    cmp rax, 0
    jl handle_error

    ; SYS_LISTEN - wait for connections
    mov rax, 50
    mov rdi, [socket_fd]
    mov rsi, 10
    syscall

accept_loop:    ; Handshake
    mov rax, 43
    mov rdi, [socket_fd]
    mov rsi, 0
    mov rdx, 0
    syscall

    cmp rax, 0
    jl handle_error
    mov [accept_fd], rax

    ; SYS_READ - recieve the request
    mov rax, 0
    mov rdi, [accept_fd]
    mov rsi, buffer
    mov rdx, 800
    syscall 

    ; Process the file request from client
    ; Init cursor
    mov rbx, buffer

find_first_space:
    cmp byte [rbx], ' '
    je found_first_space
    inc rbx
    jmp find_first_space

found_first_space:
    inc rbx     ; Skip space we finished the loop on
    mov [FILENAME_START], rbx

find_second_space:
    cmp byte [rbx], ' '
    je found_end
    inc rbx
    jmp find_second_space

found_end:
    mov byte [rbx], 0
    mov [FILENAME_END], rbx

    sub rbx, [FILENAME_START]

    cmp rbx, 1
    je single_char

read_file:
    ; SYS_OPEN
    mov rax, 2
    mov rdi, [FILENAME_START]
    mov rsi, 0
    syscall

    cmp rax, 0
    jl close_socket

    ; Save file FD
    mov r15, rax 

    ; SYS_WRITE - Send the HTML header
    mov rax, 1
    mov rdi, [accept_fd]
    mov rsi, http_response
    mov rdx, http_response_len
    syscall

read_file_loop:
    ; Read from file into file_buffer
    mov rdi, r15
    mov rsi, file_buffer
    mov rdx, 4096
    mov rax, 0
    syscall

    ; Check for EOF
    cmp rax, 0
    je close_file
    
    ; Print RAX amount of bytes from file_buffer
    mov rdx, rax
    mov rsi, file_buffer
    mov rdi, [accept_fd]
    mov rax, 1
    syscall

    jmp read_file_loop

close_file:
    mov rax, 3
    mov rdi, r15
    syscall

close_socket:
    mov rax, 3
    mov rdi, [accept_fd]
    syscall

    jmp accept_loop

    ; SYS_CLOSE
    mov rax, 3
    mov rdi, [accept_fd]
    syscall

    jmp accept_loop

handle_error:
    mov rax, 60
    mov rdi, 1
    syscall

single_char:
    mov rcx, [FILENAME_START]
    cmp byte [rcx], '/'
    jne read_file

    mov rax, index_html_str
    mov [FILENAME_START], rax
    jmp read_file
