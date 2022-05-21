#include <fcntl.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <assert.h>

#include <sys/socket.h>
#include <sys/types.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netdb.h>

#include <zlib.h>

static int hexdump_address;
void hex_dump(int ch);

int msgsize[256] = {
    /* 0x00 */ 131,		/* Ident */
    /* 0x01 */ 1,		/* Ping */
    /* 0x02 */ 1,		/* LevelInit */
    /* 0x03 */ 1024+4,		/* LevelData */
    /* 0x04 */ 7,		/* LevelEnd */
    /* 0x05 */ 0,		/* Client setblock */
    /* 0x06 */ 8,		/* SetBlock */
    /* 0x07 */ 2+64+6+2,	/* Spawn Entity */
    /* 0x08 */ 2+6+2,		/* Position */
    /* 0x09 */ 7,		/* Entity Move and Rotate */
    /* 0x0a */ 5,		/* Entity Move */
    /* 0x0b */ 4,		/* Entiry Rotate */
    /* 0x0c */ 2,		/* Remove Entity */
    /* 0x0d */ 2+64,		/* Message */
    /* 0x0e */ 1+64,		/* Disconnect Message */
    /* 0x0f */ 2,		/* SetOP */
};

uint8_t * map_blocks = 0;
uint16_t cells_x, cells_y, cells_z;
int map_len = 0;

int init_connection(int argc , char *argv[]);
int process_connection();
void print_text(char * prefix, uint8_t * str);
void pad_nbstring(uint8_t * dest, const char * str);
void decompress_start();
void decompress_block(uint8_t * buf, int len);
void decompress_end();
void z_error(int ret);

z_stream strm  = { .zalloc = Z_NULL, .zfree = Z_NULL, .opaque = Z_NULL};
int z_state = 0;

int main(int argc , char *argv[]) {
    int socket_desc = init_connection(argc, argv);
    int rv = process_connection(socket_desc);
    return rv;
}

int init_connection(int argc , char *argv[]) {
    int socket_desc;
    struct sockaddr_in server;
    struct hostent * hostaddr = 0;

    char * host = "localhost";
    int port = 25565;
    char * userid = getenv("USER");
    char * mppass = "";

    if (argc > 1) userid = argv[1];
    if (argc > 4) mppass = argv[2];
    if (argc > 3) host = argv[3];
    if (argc > 4) port = atoi(argv[4]);

    if (port <= 0 || port > 65535) {
	fprintf(stderr, "Illegal port number\n");
	exit(1);
    }

    hostaddr = gethostbyname(host);
    if(!hostaddr || hostaddr->h_addr_list[0] == 0) {
	fprintf(stderr, "Could not resolve host '%s'\n", host);
	exit(1);
    }
    
    socket_desc = socket(AF_INET , SOCK_STREAM , 0);

    memcpy(&server.sin_addr, hostaddr->h_addr_list[0], hostaddr->h_length);
    server.sin_family = AF_INET;
    server.sin_port = htons( port );

    if (connect(socket_desc , (struct sockaddr *)&server , sizeof(server)) == -1) {
	perror("Connection failed");
	exit(1);
    }

    puts("Connected");

    uint8_t wbuffer[256];

    wbuffer[0] = 0; wbuffer[1] = 7;
    pad_nbstring(wbuffer+2, userid);
    pad_nbstring(wbuffer+2+64, mppass);
    wbuffer[2+64+64] = 0;

    write(socket_desc, wbuffer, 2+64+64+1);

    return socket_desc;
}

int
process_connection(int socket_desc)
{
    uint8_t wbuffer[256];
    uint8_t buffer[8192*32];
    int total = 0;
    int used = 0;
    fd_set rfds, wfds, efds;
    struct timeval tv;
    int rv, tty_ifd = 0;

    for(;;) {
	FD_ZERO(&rfds);
	FD_ZERO(&wfds);
	FD_ZERO(&efds);

	FD_SET(tty_ifd, &rfds);      /* Data from the TTY */
	FD_SET(socket_desc, &efds);  /* Exception on the socket */
	FD_SET(socket_desc, &rfds);  /* Data from the socket */

	tv.tv_sec = 0; tv.tv_usec = 10000;
	rv = select(socket_desc+1, &rfds, &wfds, &efds, &tv);

	if (rv < 0) {
	    if (errno != EINTR) break;
	    continue;
	}
	if (rv == 0) {
	    /* TICK */
	    continue;
	}

	if( FD_ISSET(socket_desc, &efds) ) break; //END
	if( FD_ISSET(tty_ifd, &rfds) )
	{
	    char txbuf[2048];
	    rv = read(tty_ifd, txbuf, sizeof(txbuf));
	    if (rv <= 0) break;
	    if (rv > 0) {
		if (txbuf[rv-1] == '\n') rv--;
		txbuf[rv] = 0;

		wbuffer[0] = 0x0d; wbuffer[1] = 0xFF;
		pad_nbstring(wbuffer+2, txbuf);
		write(socket_desc, wbuffer, 2+64);
	    }
	}

	if( FD_ISSET(socket_desc, &rfds) ) {
	    if ((rv = read(socket_desc, &buffer[total], sizeof buffer - total)) > 0) {
		total += rv;
		while (total > used) {
		    uint8_t packet_id = buffer[used];
		    if (total >= used + msgsize[packet_id]) {
			switch (packet_id) {
			case 0x00:
			    print_text("Host:", buffer+used+2);
			    print_text("MOTD:", buffer+used+66);
			    break;
			case 0x02:
			    printf("Loading map\r"); fflush(stdout);
			    decompress_start();
			    break;
			case 0x03:
			    printf("Loading map %d%%\r", buffer[used+1027]); fflush(stdout);
			    cells_x = buffer[used+1]*256+buffer[used+2];
			    decompress_block(buffer+used+3, cells_x);
			    break;
			case 0x04:
			    decompress_end();
			    cells_x = buffer[used+1]*256+buffer[used+2];
			    cells_y = buffer[used+3]*256+buffer[used+4];
			    cells_z = buffer[used+5]*256+buffer[used+6];
			    printf("Loaded map %d,%d,%d\n", cells_x,cells_y,cells_z);
			    if (cells_x*cells_y*cells_z != map_len)
				fprintf(stderr, "WARNING: map len does not match size\n");
			    break;
			case 0x07:
			    print_text("User:", buffer+used+2);
			    break;
			case 0x0d:
			    print_text(0, buffer+used+2);
			    break;
			case 0x0e:
			    print_text("Logoff:", buffer+used+1);
			    break;
			}
			if (msgsize[packet_id] <= 0) {
			    printf("Received unknown packet id: %d\n", packet_id);
			    break;
			}

			used += msgsize[packet_id];
			if (used == total)
			    used = total = 0;
		    } else {
			if (total == sizeof(buffer)) {
			    memcpy(buffer, buffer+used, sizeof buffer - used);
			    total = sizeof buffer - used;
			    used = 0;
			}
			break;
		    }
		}
	    }
	    if (rv<=0) break;
	}
    }

    if (rv < 0) perror("Network error");

    return (rv<0);
}

void
print_text(char * prefix, uint8_t * str)
{
    static int toansi[] = { 30, 34, 32, 36, 31, 35, 33, 37 };
    if (prefix && *prefix)
	printf("%s ", prefix);

    printf("\033[;40;93m");
    int col = 0, len=64;
    while(len>0 && (str[len-1] == ' ' || str[len-1] == '\0')) len--;
    for(int i=0; i<len; i++) {
	if (col) {
	    if (isascii(str[i]) && isxdigit(str[i])) {
		if (isdigit(str[i]))
		    col = str[i] - '0';
		else
		    col = toupper(str[i] - 'A' + 10);
		if (col & 8)
		    printf("\033[40;%dm", toansi[col & 7] + 60);
		else
		    printf("\033[%d;%dm", col?40:100, toansi[col & 7]);
		col = 0;
		continue;
	    } else
		putchar('&');
	}

	if (str[i] == '&')
	    col = 1;
	else if (str[i] >= ' ' && str[i] <= '~')
	    putchar(str[i]);
	else if (str[i] == 0)
	    printf("\033[C");
	else
	    putchar('*');
    }

    printf("\033[m\n");
}

void
pad_nbstring(uint8_t * dest, const char * str)
{
    memset(dest, ' ', 64);
    memcpy(dest, str, strlen(str));
}

void
decompress_start()
{
    if (map_blocks) free(map_blocks);
    map_blocks = 0;
    map_len = 0;
    cells_x = cells_y = cells_z = 0;
    z_state = 0;
}

void
decompress_block(uint8_t * src, int src_len)
{
    int ret = Z_OK;
    if (z_state) return;

    if (map_blocks == 0) {
	uint8_t mini_buf[4];
	strm.total_out = strm.avail_out = sizeof(mini_buf);
	strm.next_out  = (Bytef *) mini_buf;
	strm.total_in  = strm.avail_in  = src_len;
	strm.next_in   = src;

	assert(inflateInit2(&strm, (MAX_WBITS + 16)) == Z_OK);

	while (src_len > 0 && strm.avail_out > 0 && ret == Z_OK)
	{
	    ret = inflate(&strm, Z_NO_FLUSH);

	    unsigned int processed = src_len - strm.avail_in;
	    src_len -= processed;
	    src += processed;
	    strm.total_in  = strm.avail_in  = src_len;
	    strm.next_in   = src;
	}
	if (strm.avail_out == 0) {
	    map_len = (mini_buf[0] << 24)
	            + (mini_buf[1] << 16)
	            + (mini_buf[2] << 8)
	            + (mini_buf[3]);
	    if (map_len <= 0) {
		fprintf(stderr, "Got an illegal map size %d\n", map_len);
		z_state = -1;
		return;
	    }

	    map_blocks = malloc(map_len);
	    if (!map_blocks) {
		perror("malloc");
		exit(1);
	    }
	    strm.total_out = strm.avail_out = map_len;
	    strm.next_out  = (Bytef *) map_blocks;
	}
    }

    if (ret == Z_OK) {
	strm.total_in  = strm.avail_in  = src_len;
	strm.next_in   = src;

	while (src_len > 0 && strm.avail_out > 0 && ret == Z_OK)
	{
	    ret = inflate(&strm, Z_NO_FLUSH);

	    unsigned int processed = src_len - strm.avail_in;
	    src_len -= processed;
	    src += processed;
	    strm.total_in  = strm.avail_in  = src_len;
	    strm.next_in   = src;
	}
    }

    if (ret == Z_STREAM_END)
	z_state = 1;
    else if (ret != Z_OK) {
	z_error(ret);
	z_state = -1;
    }
}

void
decompress_end()
{
    if (z_state >= 0) {
	if (strm.avail_out > 0)
	    printf("Uncompressed data too small -- %d left\n", strm.avail_out);
    }
    if (z_state != 1)
	printf("Uncompressed data was too large, no end of stream found.");

    inflateEnd(&strm);
}

void
z_error(int ret)
{
    if (ret == Z_STREAM_ERROR)
	printf("Decompression Error Z_STREAM_ERROR\n");
    if (ret == Z_NEED_DICT)
	printf("Decompression Error Z_NEED_DICT\n");
    if (ret == Z_MEM_ERROR)
	printf("Decompression Error Z_MEM_ERROR\n");
    if (ret == Z_DATA_ERROR)
	printf("Decompression Error Z_DATA_ERROR\n");
    if (ret == Z_BUF_ERROR)
	printf("Decompression Error Z_BUF_ERROR\n");
}

void
hex_dump(int ch)
{
static char linebuf[80];
static char buf[20];
static int pos = 0;

   if (ch != EOF)
   {
      if(!pos)
         memset(linebuf, ' ', sizeof(linebuf));
      sprintf(buf, "%02x", ch&0xFF);
      memcpy(linebuf+pos*3+(pos>7), buf, 2);

      if( ch > ' ' && ch <= '~' )
            linebuf[50+pos] = ch;
      else  linebuf[50+pos] = '.';
      pos = ((pos+1) & 0xF);
   }

   if((ch == EOF) != (pos == 0))
   {
      if (hexdump_address != -1) {
         printf("%04x: %.66s\n", hexdump_address, linebuf);
         hexdump_address += 16;
      } else
         printf(": %.66s\n", linebuf);
      pos = 0;
   }
   if (ch == EOF) hexdump_address = 0;
}
