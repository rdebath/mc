
/* cc -O3 -o bin/mini_chat mini_chat.c -lz -lm */

#include <fcntl.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <assert.h>
#include <math.h>

#if defined(__STDC__) && defined(__STDC_ISO_10646__)
#include <locale.h>
#include <wchar.h>
#endif

#include <sys/socket.h>
#include <sys/types.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netdb.h>

#include <zlib.h>

extern int msgsize[256];

#if defined(__STDC__) && defined(__STDC_ISO_10646__)
extern int cp437rom[256];
int to_cp437(int ch);
#endif

typedef struct xyzhv_t xyzhv_t;
struct xyzhv_t { int x, y, z; int8_t h, v, valid; };
typedef struct user_list_t user_list_t;
struct user_list_t { xyzhv_t posn; char name[65]; };

// This should be 128, but MCG just sends it's ID even if it's greater.
// So let's use the info if we get it.
#define MAXUSERS 255

#ifndef DEFAULT_MPPASS
#define DEFAULT_MPPASS "0"
#endif
char * server_host = "localhost";
int server_port = 25565;
char * userid = "mc";
char * mppass = DEFAULT_MPPASS;
FILE * chat_log = 0;

#define World_Pack(x, y, z) (((y) * cells_z + (z)) * cells_x + (x))
uint8_t * map_blocks = 0;
uint16_t cells_x, cells_y, cells_z;
int cells_xyz = 0, map_len = 0;
xyzhv_t posn, spawn, last_sent_posn;
user_list_t users[MAXUSERS+1];
char my_user_name[65];
int active_user_count;

int disable_ticker = 0;
int jmp_dx = 0, jmp_dz = 0;
int posn_st = 0, posn_slower = 0;
int nearest_user = -1, nearest_is_user = 0;
int64_t nearest_range = 0, nearest_crange;
#define sq_range(R) (((R)*32)*((R)*32))
int nearest_pl_v = 0, nearest_pl_h = 0, nearest_pl_dx = 0, nearest_pl_dz = 0;

int tty_enabled = 0;
int disable_cpe = 0;
int extensions_offered = 0;
int extensions_received = 0;
int sent_customblks = 0;
int extn_customblocks = 0;
int extn_longermessages = 0;

void set_args(int argc , char *argv[]);
int init_connection();
int process_connection();
void process_packet(int packet_id, uint8_t * pkt, int socket_desc);
void process_user_message(int socket_desc, char * txbuf);
void print_text(const char * prefix, const uint8_t * str);
void pad_nbstring(uint8_t * dest, const char * str);
void unpad_nbstring(uint8_t * str);
void decompress_start();
void decompress_block(uint8_t * buf, int len);
void decompress_end();
void z_error(int ret);
void send_pkt_ident(int socket_desc, char * userid, char * mppass);
void send_pkt_move(int socket_desc, xyzhv_t posn);
void send_pkt_setblock(int socket_desc, int x, int y, int z, int block);
void send_pkt_extinfo(int socket_desc);
void send_pkt_message(int socket_desc, char * txbuf);
int save_lvl_file(char * fn, int gzlevel);
void set_script_file(char * fn);
void set_script_delay(int next_delay, int per_cmd);
int script_ticker(int socket_desc);

struct timeval last_tick;
void ticker(int socket_desc);
void move_player(int);
int is_clone(char * my_name, char * their_name);

char last_motd[64];
char last_srvr[64];

#ifdef ZLIB_VERNUM
z_stream strm  = { .zalloc = Z_NULL, .zfree = Z_NULL, .opaque = Z_NULL};
int z_state = 0;
#endif

int main(int argc , char *argv[]) {
    srandom(time(0) + getpid());
#if defined(__STDC__) && defined(__STDC_ISO_10646__)
    setlocale(LC_ALL, "");
#endif
    userid = getenv("USER");
    set_args(argc, argv);
    int socket_desc = init_connection();
    int rv = process_connection(socket_desc);
    return rv;
}

void
set_args(int argc , char *argv[])
{
    int ac = 0;
    char * chat_log_name = 0;

    while(argc>1) {

	if (argc>2 && strcmp( argv[1], "-L") == 0) {
	    chat_log_name = argv[2];
	    argc-=2; argv+=2;
	} else

	if (strcmp( argv[1], "-X") == 0) {
	    disable_cpe = 1;
	    argc--; argv++;
	} else

	switch(ac) {
	case 0:
	    if (strncmp("mc://", argv[1], 5) == 0) {
		// mc://127.0.0.1:25565/Userid/mppass
		char * url = strdup(argv[1]);
		char * p1 = strchr(url+5, ':');
		char * p2 = strchr(url+5, '/');
		if (p1) *p1 = 0; if (p2) *p2 = 0;
		if ((url+5)[0])
		    server_host = strdup(url+5);
		if (p1 && (!p2 || p2>p1))
		    server_port = atoi(p1+1);
		else
		    server_port = 25565;
		if (p1) *p1 = ':'; if (p2) *p2 = '/';
		if (p2) {
		    p1 = strchr(p2+1, '/');
		    if (p1) *p1 = 0;
		    userid = strdup(p2+1);
		    if ((p2 = strchr(userid, '?')) != 0) *p2 = 0;
		    if (p1)
			mppass = strdup(p1+1);
		}
		free(url);
		ac += 3;
	    } else
		userid = argv[1];
	    ac++; argc--; argv++;
	    break;

	case 1: mppass = argv[1]; ac++; argc--; argv++; break;
	case 2: server_host = argv[1]; ac++; argc--; argv++; break;
	case 3: server_port = atoi(argv[1]); ac++; argc--; argv++; break;
	default:
	    fprintf(stderr, "Too many arguments with '%s'\n", argv[1]);
	    exit(1);
	}

	if (server_port <= 0 || server_port > 65535) {
	    fprintf(stderr, "Illegal port number\n");
	    exit(1);
	}
    }

    if (chat_log_name) {
	chat_log = fopen(chat_log_name, "a");
	if (!chat_log)
	    perror(chat_log_name);
	else
	    setlinebuf(chat_log);
    }
}

int init_connection()
{
    int socket_desc;
    struct sockaddr_in server;
    struct hostent * hostaddr = 0;

    hostaddr = gethostbyname(server_host);
    if(!hostaddr || hostaddr->h_addr_list[0] == 0) {
	fprintf(stderr, "Could not resolve host '%s'\n", server_host);
	exit(1);
    }

    socket_desc = socket(AF_INET , SOCK_STREAM , 0);

    memcpy(&server.sin_addr, hostaddr->h_addr_list[0], hostaddr->h_length);
    server.sin_family = AF_INET;
    server.sin_port = htons( server_port );

    if (connect(socket_desc , (struct sockaddr *)&server , sizeof(server)) == -1) {
	perror("Connection failed");
	exit(1);
    }

    send_pkt_ident(socket_desc, userid, mppass);

    return socket_desc;
}

int
process_connection(int socket_desc)
{
    uint8_t buffer[8192];
    int total = 0;
    int used = 0;
    fd_set rfds, wfds, efds;
    struct timeval tv;
    int rv, tty_ifd = 0;

    for(;;) {
	FD_ZERO(&rfds);
	FD_ZERO(&wfds);
	FD_ZERO(&efds);

	if (tty_enabled)
	    FD_SET(tty_ifd, &rfds);  /* Data from the TTY */
	FD_SET(socket_desc, &efds);  /* Exception on the socket */
	FD_SET(socket_desc, &rfds);  /* Data from the socket */

	tv.tv_sec = 0; tv.tv_usec = 10000;
	rv = select(socket_desc+1, &rfds, &wfds, &efds, &tv);

	if (rv < 0) {
	    // The select errored, EINTR is not really one.
	    if (errno != EINTR) break;
	    continue;
	}
	if (rv == 0) {
	    /* TICK: The select timed out, anything to do? */
	    if (script_ticker(socket_desc)) continue;
	    ticker(socket_desc);
	    continue;
	}

	if( FD_ISSET(socket_desc, &efds) ) break; // Bad socket -- bye

	if( FD_ISSET(tty_ifd, &rfds) )
	{
	    char txbuf[2048];
	    rv = read(tty_ifd, txbuf, sizeof(txbuf));
	    if (rv <= 0) break;
	    if (rv > 0) {
		if (txbuf[rv-1] == '\n') rv--;
		if (rv > 0) {
		    txbuf[rv] = 0;
		    process_user_message(socket_desc, txbuf);
		}
	    }
	}

	if( FD_ISSET(socket_desc, &rfds) ) {
	    if ((rv = read(socket_desc, &buffer[total], sizeof buffer - total)) <= 0) {
		// We should always get something 'cause of the select()
		// This is bad.
		break;
	    } else {
		total += rv; // we now have rv more bytes in our buffer.
		while (total > used) {
		    uint8_t packet_id = buffer[used];
		    if (total < used + msgsize[packet_id]) {
			// We don't have enough so we need to read() more
			if (total == sizeof(buffer)) {
			    // but if the buffer is full we need to free up space.
			    memcpy(buffer, buffer+used, sizeof buffer - used);
			    total = sizeof buffer - used;
			    used = 0;
			}
			break; // Read more.
		    } else {
			// We have enough bytes for packet number [packet_id]
			int plen = msgsize[packet_id];
			if (msgsize[packet_id] <= 0) {
			    printf("Received unknown packet id: %d\n", packet_id);
			    plen = 1;
			} else
			    process_packet(packet_id, buffer+used, socket_desc);

			// Add the bytes we've just used.
			used += plen;
			// If we've used everything clear the buffer.
			if (used == total)
			    used = total = 0;
		    }
		}
	    }
	}

	if (script_ticker(socket_desc)) continue;
	ticker(socket_desc);
    }

    if (rv < 0) perror("Network error");

    return (rv<0);
}

void
process_packet(int packet_id, uint8_t * pkt, int socket_desc)
{
    int uid,x,y,z,h,v,b;
    switch (packet_id) {
    case 0x00:
	if (memcmp(pkt+2, last_srvr, 64) != 0) {
	    print_text("Host:", pkt+2);
	    memcpy(last_srvr, pkt+2, 64);
	}
	if (memcmp(pkt+66, last_motd, 64) != 0) {
	    print_text("MOTD:", pkt+66);
	    memcpy(last_motd, pkt+66, 64);
	}
	break;
    case 0x02:
#ifdef ZLIB_VERNUM
	printf("Loading map\r"); fflush(stdout);
	decompress_start();
#endif
	break;
    case 0x03:
#ifdef ZLIB_VERNUM
	printf("Loading map %d%%\r", pkt[1027]); fflush(stdout);
	b = pkt[1]*256+pkt[2];
	decompress_block(pkt+3, b);
#endif
	break;
    case 0x04:
	cells_x = pkt[1]*256+pkt[2];
	cells_y = pkt[3]*256+pkt[4];
	cells_z = pkt[5]*256+pkt[6];
	cells_xyz = cells_x*cells_y*cells_z;
#ifdef ZLIB_VERNUM
	decompress_end();
	printf("Loaded map %d,%d,%d\n", cells_x,cells_y,cells_z);
	if (cells_xyz != map_len)
	    fprintf(stderr, "WARNING: map len does not match size\n");
#else
	printf("Received map %d,%d,%d\n", cells_x,cells_y,cells_z);
#endif
	tty_enabled = 1;
	break;
    case 0x06:
	if (!map_blocks) break;
	x = pkt[1]*256+pkt[2];
	y = pkt[3]*256+pkt[4];
	z = pkt[5]*256+pkt[6];
	b = pkt[7];
	if (x>=0 && x<cells_x && y>=0 && y<cells_y && z>=0 && z<cells_z)
	    map_blocks[World_Pack(x,y,z)] = b;
	break;
    case 0x07:
	uid = pkt[1];
	x = pkt[66]*256+pkt[67];
	y = pkt[68]*256+pkt[69];
	z = pkt[70]*256+pkt[71];
	h = pkt[72];
	v = pkt[73];
	if (uid == 255) y += 22;
	if (active_user_count < 20) {
	    char buf[256];
	    sprintf(buf, "User %d @(%.2f,%.2f,%.2f,%d,%d)",
		    uid, x/32.0,(y-51)/32.0,z/32.0,h*360/256,v*360/256);
	    print_text(buf, pkt+2);
	}
	unpad_nbstring(pkt+2);
	if (uid == 255) {
	    posn.x = x;
	    posn.y = y-29;
	    posn.z = z;
	    posn.h = h;
	    posn.v = v;
	    posn.valid = 1;
	    spawn = posn;
	    memcpy(my_user_name, pkt+2, sizeof(my_user_name));
	} else if (uid < MAXUSERS) {
	    if (!users[uid].posn.valid) active_user_count++;
	    users[uid].posn.x = x;
	    users[uid].posn.y = y-29;
	    users[uid].posn.z = z;
	    users[uid].posn.h = h;
	    users[uid].posn.v = v;
	    users[uid].posn.valid = 1;
	    memcpy(users[uid].name, pkt+2, sizeof(users[uid].name));
	}
	break;
    case 0x08:
	uid = pkt[1];
	x = pkt[2]*256+pkt[3];
	y = pkt[4]*256+pkt[5];
	z = pkt[6]*256+pkt[7];
	h = pkt[8];
	v = pkt[9];
	if (uid == 255) {
	    printf("You've been teleported to (%.2f,%.2f,%.2f,%d,%d)\n",
		    x/32.0,(y-29)/32.0,z/32.0,h*360/256,v*360/256);

	    posn.x = x;
	    posn.y = y-7;
	    posn.z = z;
	    posn.h = h;
	    posn.v = v;
	    posn.valid = 1;
	    if (!spawn.valid) spawn = posn;
	} else if (uid < MAXUSERS) {
	    users[uid].posn.x = x;
	    users[uid].posn.y = y-29;
	    users[uid].posn.z = z;
	    users[uid].posn.h = h;
	    users[uid].posn.v = v;
	    users[uid].posn.valid = 1;
	    move_player(uid);
	}
	break;
    case 0x09:
	uid = pkt[1];
	x = pkt[2];
	y = pkt[3];
	z = pkt[4];
	h = pkt[5];
	v = pkt[6];
	if (uid < MAXUSERS) {
	    users[uid].posn.x += (signed char) x;
	    users[uid].posn.y += (signed char) y;
	    users[uid].posn.z += (signed char) z;
	    users[uid].posn.h = h;
	    users[uid].posn.v = v;
	    move_player(uid);
	}
	break;
    case 0x0a:
	uid = pkt[1];
	x = pkt[2];
	y = pkt[3];
	z = pkt[4];
	if (uid < MAXUSERS) {
	    users[uid].posn.x += (signed char) x;
	    users[uid].posn.y += (signed char) y;
	    users[uid].posn.z += (signed char) z;
	    move_player(uid);
	}
	break;
    case 0x0b:
	uid = pkt[1];
	h = pkt[1];
	v = pkt[2];
	if (uid < MAXUSERS) {
	    users[uid].posn.h = h;
	    users[uid].posn.v = v;
	    move_player(uid);
	}
	break;
    case 0x0c:
	uid = pkt[1];
	if (uid < MAXUSERS) {
	    if (users[uid].posn.valid) active_user_count++;
	    users[uid].posn.valid = 0;
	}
	move_player(255);
	break;
    case 0x0d:
	print_text(0, pkt+2);
	break;
    case 0x0e:
	print_text("Logoff:", pkt+1);
	break;
    case 0x10:
	print_text("Server Software:", pkt+1);
	extensions_offered = pkt[65]*256+pkt[66];
	break;
    case 0x11:
	unpad_nbstring(pkt+1);
	if (strncmp("CustomBlocks", (char*)pkt+1, 64) == 0)
	    extn_customblocks=1;
	if (strncmp("LongerMessages", (char*)pkt+1, 64) == 0)
	    extn_longermessages=1;
	extensions_received++;
	if (extensions_received == extensions_offered)
	    send_pkt_extinfo(socket_desc);
	break;
    case 0x13:
	if (!sent_customblks) {
	    uint8_t wbuffer[16];
	    wbuffer[0] = 0x13; wbuffer[1] = 1;
	    write(socket_desc, wbuffer, 2);
	    sent_customblks = 1;
	}
	break;
    }
}

void
print_text(const char * prefix, const uint8_t * str)
{
    static int toansi[] = { 30, 34, 32, 36, 31, 35, 33, 37 };
    if (prefix && *prefix)
	printf("%s \033[;40;97m", prefix);
    else
	printf("\033[;40;93m");
    int col = 0, len=64;
    while(len>0 && (str[len-1] == ' ' || str[len-1] == '\0')) len--;
    if (chat_log) {
	if (prefix && *prefix)
	    fprintf(chat_log, "%s %.*s\n", prefix, len, str);
	else
	    fprintf(chat_log, "%.*s\n", len, str);
    }
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
#if defined(__STDC__) && defined(__STDC_ISO_10646__)
	else if (cp437rom[str[i]] >= 160)
	    printf("%lc", cp437rom[str[i]]);
#endif
	else
	    printf("\\%03o", str[i]);
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
unpad_nbstring(uint8_t * str)
{
    uint8_t * p = str+63;
    while(p>str && (*p == ' ' || *p == 0)) { *p = 0; p--; }
}

#if defined(__STDC__) && defined(__STDC_ISO_10646__)
int cp437rom[256] = {
    0x0000, 0x263a, 0x263b, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022,
    0x25d8, 0x25cb, 0x25d9, 0x2642, 0x2640, 0x266a, 0x266b, 0x263c,
    0x25b6, 0x25c0, 0x2195, 0x203c, 0x00b6, 0x00a7, 0x25ac, 0x21a8,
    0x2191, 0x2193, 0x2192, 0x2190, 0x221f, 0x2194, 0x25b2, 0x25bc,
    0x0020, 0x0021, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027,
    0x0028, 0x0029, 0x002a, 0x002b, 0x002c, 0x002d, 0x002e, 0x002f,
    0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037,
    0x0038, 0x0039, 0x003a, 0x003b, 0x003c, 0x003d, 0x003e, 0x003f,
    0x0040, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047,
    0x0048, 0x0049, 0x004a, 0x004b, 0x004c, 0x004d, 0x004e, 0x004f,
    0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057,
    0x0058, 0x0059, 0x005a, 0x005b, 0x005c, 0x005d, 0x005e, 0x005f,
    0x0060, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067,
    0x0068, 0x0069, 0x006a, 0x006b, 0x006c, 0x006d, 0x006e, 0x006f,
    0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076, 0x0077,
    0x0078, 0x0079, 0x007a, 0x007b, 0x007c, 0x007d, 0x007e, 0x2302,
    0x00c7, 0x00fc, 0x00e9, 0x00e2, 0x00e4, 0x00e0, 0x00e5, 0x00e7,
    0x00ea, 0x00eb, 0x00e8, 0x00ef, 0x00ee, 0x00ec, 0x00c4, 0x00c5,
    0x00c9, 0x00e6, 0x00c6, 0x00f4, 0x00f6, 0x00f2, 0x00fb, 0x00f9,
    0x00ff, 0x00d6, 0x00dc, 0x00a2, 0x00a3, 0x00a5, 0x20a7, 0x0192,
    0x00e1, 0x00ed, 0x00f3, 0x00fa, 0x00f1, 0x00d1, 0x00aa, 0x00ba,
    0x00bf, 0x2310, 0x00ac, 0x00bd, 0x00bc, 0x00a1, 0x00ab, 0x00bb,
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
    0x2555, 0x2563, 0x2551, 0x2557, 0x255d, 0x255c, 0x255b, 0x2510,
    0x2514, 0x2534, 0x252c, 0x251c, 0x2500, 0x253c, 0x255e, 0x255f,
    0x255a, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256c, 0x2567,
    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256b,
    0x256a, 0x2518, 0x250c, 0x2588, 0x2584, 0x258c, 0x2590, 0x2580,
    0x03b1, 0x00df, 0x0393, 0x03c0, 0x03a3, 0x03c3, 0x00b5, 0x03c4,
    0x03a6, 0x0398, 0x03a9, 0x03b4, 0x221e, 0x03c6, 0x03b5, 0x2229,
    0x2261, 0x00b1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00f7, 0x2248,
    0x00b0, 0x2219, 0x00b7, 0x221a, 0x207f, 0x00b2, 0x25a0, 0x00a0
};

static unsigned char UTFlen[] = {
    0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    /*             3, 3, 3, 4, 4, 4, 4, 5, 5, 6, 0 // Unicode 2.0 */
};

int ucs = 0, utf8state = 0;

int
to_cp437(int ch)
{
    if (ch < 0x80) { utf8state = 0; return ch;}
    if (utf8state == 0 && ch >= 0xC0) {
	utf8state = UTFlen[ch&0x3F];
	ucs = (ch&0x1F);
	if (utf8state == 2) ucs &= 0xF;
	if (utf8state == 3) ucs &= 0x7;
    } else if (utf8state != 0 && ch >= 0x80 && ch < 0xC0) {
	ucs = (ucs << 6) + (ch & 0x3F);
	utf8state--;
	if (utf8state == 0) {
	    int i;
	    for(i=0; i<256; i++) {
		if (ucs == cp437rom[i])
		    return i;
	    }
	    return 0xA8;
	}
    }
    return 0;
}
#endif

#ifdef ZLIB_VERNUM
void
decompress_start()
{
    if (map_blocks) free(map_blocks);
    map_blocks = 0;
    cells_xyz = map_len = 0;
    cells_x = cells_y = cells_z = 0;
    z_state = 0;
    spawn.valid = 0;
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
#endif

void
send_pkt_ident(int socket_desc, char * userid, char * mppass)
{
    uint8_t wbuffer[256];
    wbuffer[0] = 0; wbuffer[1] = 7;
    pad_nbstring(wbuffer+2, userid);
    pad_nbstring(wbuffer+2+64, mppass);
    wbuffer[2+64+64] = disable_cpe?0:0x42;
    write(socket_desc, wbuffer, 2+64+64+1);
}

void
send_pkt_move(int socket_desc, xyzhv_t posn)
{
    uint8_t wbuffer[256];
    wbuffer[0] = 8;
    wbuffer[1] = 255;
    wbuffer[2] = posn.x>>8;
    wbuffer[3] = posn.x;
    wbuffer[4] = (posn.y+29)>>8;
    wbuffer[5] = (posn.y+29);
    wbuffer[6] = posn.z>>8;
    wbuffer[7] = posn.z;
    wbuffer[8] = posn.h;
    wbuffer[9] = posn.v;
    write(socket_desc, wbuffer, 10);
}

void
send_pkt_setblock(int socket_desc, int x, int y, int z, int block)
{
    int moved = 0;
    int dx = x-posn.x/32, dy = y-posn.y/32, dz = z-posn.z/32;
    if (posn.valid && dx*dx+dy*dy+dz*dz > 25) {
	xyzhv_t npos = posn;
	npos.x = x*32+16;
	npos.y = y*32+64;
	npos.z = z*32+16;

        if (npos.z>posn.z) npos.h = 128;
        else if (npos.z<posn.z) npos.h = 0;
        else if (npos.x>posn.x) npos.h = 64;
        else if (npos.x<posn.x) npos.h = -64;

	send_pkt_move(socket_desc, npos);
	moved = 1;
	posn = npos;
    }
    uint8_t wbuffer[256];
    wbuffer[0] = 5;
    wbuffer[1] = (x>>8);
    wbuffer[2] = (x&0xFF);
    wbuffer[3] = (y>>8);
    wbuffer[4] = (y&0xFF);
    wbuffer[5] = (z>>8);
    wbuffer[6] = (z&0xFF);
    wbuffer[7] = (block!=0);
    wbuffer[8] = block?block:1;
    write(socket_desc, wbuffer, 9);
}

void
send_pkt_extinfo(int socket_desc)
{
static struct tx_extn { char extname[65]; uint8_t vsn; } extns[] =
    {
	{ "CustomBlocks", 1 },
	{ "FullCP437", 1 },
	{ "EmoteFix", 1 },
	{ "InstantMOTD", 1 },
	{ "LongerMessages", 1 }
    };

    const int extno = sizeof(extns)/sizeof(*extns);
    uint8_t wbuf[100 + 69*extno];
    uint8_t * wbuffer = wbuf;

    wbuffer[0] = 0x10;
    pad_nbstring(wbuffer+1, "minichat");
    wbuffer[65] = 0;
    wbuffer[66] = extno;
    wbuffer += 67;

    for(int i = 0; i < extno; i++) {

	wbuffer[0] = 0x11;
	pad_nbstring(wbuffer+1, extns[i].extname);
	wbuffer[65] = 0;
	wbuffer[66] = 0;
	wbuffer[67] = 0;
	wbuffer[68] = extns[i].vsn;
	wbuffer += 69;
    }
    write(socket_desc, wbuf, wbuffer-wbuf);
}

void
process_user_message(int socket_desc, char * txbuf)
{
    char cmd[64], fn[2048], xtra[64];
    int b, x, y, z;

    if (sscanf(txbuf, "/%60s", cmd) == 1) {
	if (strcasecmp(cmd, "pl") == 0) {
	    // Convert a "/pl" command into a setblock packet
	    if (sscanf(txbuf, "/%60s %d %d %d %d %60s", cmd, &b, &x, &y, &z, xtra) == 5) {
		if (b >= 0 && b < 66) {
		    send_pkt_setblock(socket_desc, x, y, z, b);
		    return;
		}
	    }
	} else if (strcasecmp(cmd, "export") == 0) {
	    if (sscanf(txbuf, "/%60s %2040s %2s", cmd, fn, xtra) == 2)
		save_lvl_file(fn, 6);
	    else
		fprintf(stderr, "Usage: /export filename.lvl\n");
	    return;
	} else if (strcasecmp(cmd, "script") == 0) {
	    if (sscanf(txbuf, "/%60s %2040s %2s", cmd, fn, xtra) == 2)
		set_script_file(fn);
	    else
		fprintf(stderr, "Usage: /script filename.mc\n");
	    return;
	} else if (strcasecmp(cmd, "delay") == 0) {
	    x = y = -1;
	    if (sscanf(txbuf, "/%60s %d %d", cmd, &x, &y) >= 2) {
		set_script_delay(x, y);
		return;
	    }
	}
    }

    send_pkt_message(socket_desc, txbuf);
}

void
send_pkt_message(int socket_desc, char * txbuf)
{
    int len = strlen(txbuf);
    char txwbuf[len+2];
#if defined(__STDC__) && defined(__STDC_ISO_10646__)
    int i, j;
    for(i=j=0; txbuf[i]; i++) {
	int ch = to_cp437((uint8_t)txbuf[i]);
	if (ch)
	    txwbuf[j++] = ch;
    }
    txwbuf[j] = 0;
    txbuf = txwbuf;
#endif
    uint8_t wbuffer[128];
    wbuffer[0] = 0x0d; wbuffer[1] = 0xFF;
    while(len>64) {
	if (extn_longermessages) wbuffer[1] = 1;
	memcpy(wbuffer+2, txbuf, 64);
	write(socket_desc, wbuffer, 2+64);
	txbuf+=64; len-=64;
    }
    if (extn_longermessages) wbuffer[1] = 0;
    pad_nbstring(wbuffer+2, txbuf);
    write(socket_desc, wbuffer, 2+64);
}

/* Message packet sizes, send and receive use the same list.
 * Note that the protocol does NOT include length fields.
 *
 * This is all defined base and CPE packets.
 */
int msgsize[256] = {
    /* 0x00 */ 131,             /* Ident */
    /* 0x01 */ 1,               /* Ping */
    /* 0x02 */ 1,               /* LevelInit */
    /* 0x03 */ 1024+4,          /* LevelData */
    /* 0x04 */ 7,               /* LevelEnd */
    /* 0x05 */ 0,               /* Client setblock */
    /* 0x06 */ 8,               /* SetBlock */
    /* 0x07 */ 2+64+6+2,        /* Spawn Entity */
    /* 0x08 */ 2+6+2,           /* Position */
    /* 0x09 */ 7,               /* Entity Move and Rotate */
    /* 0x0a */ 5,               /* Entity Move */
    /* 0x0b */ 4,               /* Entiry Rotate */
    /* 0x0c */ 2,               /* Remove Entity */
    /* 0x0d */ 2+64,            /* Message */
    /* 0x0e */ 1+64,            /* Disconnect Message */
    /* 0x0f */ 2,               /* SetOP */

    /* CPE starts here */
    /* 0x10 */ 67,              /* ExtInfo */
    /* 0x11 */ 69,              /* ExtEntry */
    /* 0x12 */ 3,               /* ClickDistance */
    /* 0x13 */ 2,               /* CustBlock */

    /* These are not implemented */
    /* 0x14 */ 3,               /* HELDBLOCK */
    /* 0x15 */ 134,             /* SETHOTKEY */
    /* 0x16 */ 196,             /* PLAYERNAME */
    /* 0x17 */ 130,             /* ADDENTv1 */
    /* 0x18 */ 3,               /* RMENT */
    /* 0x19 */ 8,               /* MAPCOLOUR */
    /* 0x1a */ 86,              /* ADDZONE */
    /* 0x1b */ 2,               /* RMZONE */
    /* 0x1c */ 4,               /* BLOCKPERM */
    /* 0x1d */ 66,              /* CHANGEMDL */
    /* 0x1e */ 69,              /* MAPAPPEAR */
    /* 0x1f */ 2,               /* WEATHER */
    /* 0x20 */ 8,               /* HACKCTL */
    /* 0x21 */ 138,             /* ADDENT */
    /* 0x22 */ 15,              /* PLAYERCLK */ /*ClientSend*/
    /* 0x23 */ 80,              /* BLOCKDEF */
    /* 0x24 */ 2,               /* BLOCKUNDEF */
    /* 0x25 */ 88,              /* BLOCKDEF2 */
    /* 0x26 */ 1282,            /* BULKUPDATE */
    /* 0x27 */ 6,               /* TEXTCOLOUR */
    /* 0x28 */ 65,              /* TEXURL */
    /* 0x29 */ 6,               /* MAPPROP */
    /* 0x2a */ 7,               /* ENTITYPROP */
    /* 0x2b */ 4,               /* PINGPONG */  /*ClientSend&Rcv*/
    /* 0x2c */ 3,               /* INVORDER */
    /* 0x2d */ 3,               /* HOTBAR */
    /* 0x2e */ 9,               /* SETSPAWN */
    /* 0x2f */ 16,              /* VELOCITY */
    /* 0x30 */ 36,              /* DEFEFFECT */
    /* 0x31 */ 26,              /* USEEFFECT */
    /* 0x32 */ 116,             /* DEFMODEL */
    /* 0x33 */ 167,             /* DEFMODELPART */
    /* 0x34 */ 2,               /* RMMODEL */
    /* 0x35 */ 66,              /* PLUGINMSG */
    /* 0x36 */ 11,              /* TELEPORT */
    0

};

void
ticker(int socket_desc)
{
    struct timeval tv;
    gettimeofday(&tv, 0);
    int csec = ((tv.tv_sec*1000000+tv.tv_usec) - (last_tick.tv_sec*1000000+last_tick.tv_usec))/10000;
    if (csec == 0) return;
    last_tick = tv;

    if (!posn.valid || disable_ticker) return;
    posn_slower = (posn_slower+1)%200;

    if (posn_slower == 50 || posn_slower == 150) move_player(255);

    if (posn_slower%5  == 0) {

	if (map_blocks && cells_xyz != 0) {
	    int x = posn.x/32, y = (posn.y-6)/32, z = posn.z/32;
	    int xoff = posn.x - (x*32+16);
	    int zoff = posn.z - (z*32+16);

	    int off, b[3] = {0,0,0};
	    int jumped = (!!jmp_dz + !!jmp_dx);

	    // Move toward distant users.
	    if (!jumped && nearest_user >= 0 && nearest_range > sq_range(12)) {
		xoff += nearest_pl_dx; zoff += nearest_pl_dz;
	    }

	    if (jumped) {
		// We're jumping to "about" the centre of the block.
		xoff = ((rand()>>8)%15 - 7);
		zoff = ((rand()>>8)%15 - 7);
		x += jmp_dx; z += jmp_dz; jmp_dx=jmp_dz=0;
	    }

	    if (x < 0 || x >= cells_x || z < 0 || z >= cells_x) {
		if (spawn.valid) {
		    x = spawn.x/32; y = spawn.y/32; z = spawn.z/32;
		    jumped = 1;
		}
	    }
	    if (x < 0 || x >= cells_x || z < 0 || z >= cells_x) {
		x = cells_x/2; y = cells_y; z = cells_z/2;
		jumped = 1;
	    }

	    for(off=-1; off<2; off++) {
		int y1 = y+off;
		int b1 = 0;
		if (y1 < 0) b1 = 7; else if (y1 >= cells_y) b1 = 0;
		else b1 = map_blocks[World_Pack(x, y1, z)];
		if (b1 == 44 || b1 == 50) b1 = 2;
		else if (b1 == 8 || b1 == 9 || b1 == 10 || b1 == 11) b1 = 3;
		else b1 = ! (b1 == 0 || b1 == 6 || b1 == 37 || b1 == 38 ||
		    b1 == 39 || b1 == 40 || b1 == 51 || b1 == 53 || b1 == 54);
		b[off+1] = b1;
	    }

	    int mov = 1;
	    if (b[1] || b[2]) y++; else if (!b[0]) y--; else mov = 0;
	    posn.x = x * 32 + 16 + xoff;
	    posn.y = y * 32 + 22 - 16*(mov == 0 && b[0] == 2) - 3*(mov == 0 && b[0] == 3);
	    posn.z = z * 32 + 16 + zoff;
	    posn.v = 0;
	    if (jumped || mov) move_player(255);
	}

	if (active_user_count > 19 || nearest_is_user) {
	    if (!posn_st) posn_st = (random()&2)-1;
	    posn.h+=posn_st;
	    if (!posn.h) posn_st = -posn_st;
	}
    }

    if (nearest_user >= 0 && nearest_range < sq_range(5) && nearest_is_user) {
	posn.v = nearest_pl_v;
	posn.h = nearest_pl_h;
	posn_st = 0;
    }

    if (posn_slower != 0 &&
	last_sent_posn.valid &&
	last_sent_posn.x == posn.x &&
	last_sent_posn.y == posn.y &&
	last_sent_posn.z == posn.z &&
	last_sent_posn.h == posn.h &&
	last_sent_posn.v == posn.v)
	return;

    last_sent_posn = posn;
    last_sent_posn.valid = 1;

    send_pkt_move(socket_desc, posn);
}

void
calculate_stare_angle(int player_x, int player_y, int player_z, int tx, int ty, int tz, int * ph, int * pv)
{
    int player_eye = 56;
    int target_eye = 56;

    double dx = tx - player_x;
    double dy = (ty+target_eye) - (player_y+player_eye);
    double dz = tz - player_z;

    double range = sqrt(dx*dx+dy*dy+dz*dz);
    if (range != 0) {
	double ir = 1/range;
	dx *= ir; dy *= ir; dz *= ir;
    }

    double radian2byte = 256 / (2 * M_PI);

    *ph = atan2(dx, -dz) * radian2byte;
    *pv = asin(-dy) * radian2byte;
}

void
move_player(int uid)
{
    if (uid == 255) {
	nearest_user = -1;
	nearest_is_user = 0;
	for(int i=0; i<MAXUSERS; i++)
	    if(i!=uid && users[i].posn.valid) move_player(i);
	return;
    }
    if (!users[uid].posn.valid) return;
    int x = users[uid].posn.x;
    int y = users[uid].posn.y;
    int z = users[uid].posn.z;
    // int h = users[uid].posn.h;
    // int v = users[uid].posn.v;

    if (!posn.valid) {
	nearest_user = -1;
	return;
    }

    int64_t range, crange;
    int isclone = 0;
    {
	int64_t rx = abs(x - posn.x);
	int64_t ry = abs(y - posn.y);
	int64_t rz = abs(z - posn.z);
	crange = range = rx*rx + ry*ry + rz*rz;
	isclone = is_clone(my_user_name, users[uid].name);
	if (isclone) crange *= 1048576;
    }
    if (nearest_user < 0 || crange < nearest_crange || nearest_user == uid) {
	nearest_user = uid;
	nearest_range = range;
	nearest_crange = crange;
	nearest_is_user = !isclone;
    }
    if (uid == nearest_user) {
	calculate_stare_angle(posn.x, posn.y, posn.z, x, y, z, &nearest_pl_h, &nearest_pl_v);
	nearest_pl_dx = (posn.x < x) - (x < posn.x);
	nearest_pl_dz = (posn.z < z) - (z < posn.z);
	if (abs(posn.z-z) > abs(posn.x-x)*5) nearest_pl_dx = 0;
	if (abs(posn.x-x) > abs(posn.z-z)*5) nearest_pl_dz = 0;
	if (abs(posn.x-x) < 32) nearest_pl_dx = 0;
	if (abs(posn.z-z) < 32) nearest_pl_dz = 0;
    }

    // Is there someone close?
    if (abs(posn.y-y) > 96 || abs(posn.x-x) > 46 || abs(posn.z-z) > 46) return;
    if (posn.z != z && abs(posn.z-z) < abs(posn.x-x)*4 &&
	posn.x != x && abs(posn.x-x) < abs(posn.z-z)*4)
    {
	if (random()&6) { jmp_dx = posn.x-x; jmp_dx = (jmp_dx > 0) - (jmp_dx < 0); }
	if (random()&6) { jmp_dz = posn.z-z; jmp_dz = (jmp_dz > 0) - (jmp_dz < 0); }
    } else if (abs(posn.x-x) > abs(posn.z-z) && posn.x != x) {
	jmp_dx = posn.x-x; jmp_dx = (jmp_dx > 0) - (jmp_dx < 0);
	if ((random()&7) == 0) jmp_dz = (random()&2)-1;
    } else if (posn.z != z) {
	jmp_dz = posn.z-z; jmp_dz = (jmp_dz > 0) - (jmp_dz < 0);
	if ((random()&7) == 0) jmp_dx = (random()&2)-1;
    } else {
	jmp_dz = (random()&2)-1;
	jmp_dx = (random()&2)-1;
    }
}

int
is_clone(char * my_name, char * their_name)
{
    // Are the two usernames "similar" ?
    char *m, *t;
    for(m=my_name, t=their_name; *t && *m; )
    {
	if (*m == '&' && m[1] != 0) {m+=2; continue;}
	if (*t == '&' && t[1] != 0) {t+=2; continue;}
	if (*t >= '0' && *t <= '9' && *m >= '0' && *m <= '9')
	    return 1;
	if (*t != *m)
	    return 0;
	m++; t++;
    }
    return 1;
}

/**************************************************************************/
/*
 * This writes a *.lvl file.
 *
 * The lvl file will only contain blocks; Physics and Zones are not supported.
 */

#define Block_Cust	66

static void
write_lvl_int16(FILE *ofd, int val)
{
    putc(val&0xFF, ofd);
    putc((val>>8), ofd);
}

void
write_lvl_header(FILE *savefile)
{
    write_lvl_int16(savefile, 1874);
    write_lvl_int16(savefile, cells_x);
    write_lvl_int16(savefile, cells_z);
    write_lvl_int16(savefile, cells_y);
    write_lvl_int16(savefile, spawn.x/32);
    write_lvl_int16(savefile, spawn.z/32);
    write_lvl_int16(savefile, (spawn.y+51)/32);
    putc(spawn.h, savefile);
    putc(spawn.v, savefile);
    putc(0, savefile); // VisitAccess.Min;
    putc(0, savefile); // BuildAccess.Min;
}

void
write_lvl_block_section(FILE *savefile, int64_t len)
{

    for (intptr_t i = 0; i<len; i++) {
	int b = map_blocks[i];
	if (b >= Block_Cust) {
	    if (b < 256)
		b = 163; // "custom_block"
	    else if (b < 512)
		b = 198; // "custom_block_2"
	    else
		b = 199; // "custom_block_3"
	}
	putc(b & 0xFF, savefile);
    }
}

void
write_lvl_customblock_section(FILE *savefile, int64_t len)
{
    putc(0xBD, savefile);
    int chunks_x = (cells_x+15)/16;
    int chunks_y = (cells_y+15)/16;
    int chunks_z = (cells_z+15)/16;

    for (int y = 0; y < chunks_y; y++)
	for (int z = 0; z < chunks_z; z++)
	    for (int x = 0; x < chunks_x; x++)
	    {
		int flg = 0;
		uint8_t chunk[4096];
		memset(chunk, 0, sizeof(chunk));

		for(int cy = 0; cy < 16; cy++)
		{
		    if (y+cy >= cells_y) continue;
		    for(int cz = 0; cz < 16; cz++)
		    {
			if (z+cz >= cells_z) continue;
			for(int cx = 0; cx < 16; cx++)
			{
			    if (x+cx >= cells_x) continue;

			    uint64_t ind = World_Pack(x*16+cx,y*16+cy,z*16+cz);
			    if (ind >= len) continue;
			    int b = map_blocks[ind];
			    if (b >= Block_Cust)
				flg = 1;
			    chunk[cy << 8 | cz << 4 | cx] = (b & 0xFF);
			}
		    }
		}

		putc(flg, savefile);
		if (!flg) continue;

		fwrite(chunk, sizeof(chunk), 1, savefile);
	    }

}

int
save_lvl_file(char * fn, int gzlevel)
{
    if (!fn || *fn == 0) return -1;
    char cmdbuf[PATH_MAX];

    fprintf(stderr, "Saving level file \"%s\".\n", fn);

    snprintf(cmdbuf, sizeof(cmdbuf), "gzip -n -%d >'%s'", gzlevel, fn);
    FILE *savefile = popen(cmdbuf, "w");

    if (!savefile) {
	perror(fn);
	return -1;
    }

    write_lvl_header(savefile);

    int64_t len = (int64_t)cells_x * cells_y * cells_z;
    if (len > cells_xyz) len = cells_xyz;
    if (len >= ((int64_t)2<<31)) len = ((int64_t)2<<31) -1;

    write_lvl_block_section(savefile, len);

    write_lvl_customblock_section(savefile, len);

    // Empty physics = ""
    // Empty Zones = ""

    int rv = pclose(savefile);
    if (rv) {
	fprintf(stderr, "Save failed error Z%d\n", rv);
    }

    if (rv) return -1;
    return 0;
}

/**************************************************************************/
/*
 * Trivial script running
 */

struct timeval last_script_tick;
FILE * script_fd = 0;
int ms_per_cmd = 26;
int ms_available = 0;

void
set_script_delay(int next_delay, int per_cmd)
{
    if (next_delay > 0)
	ms_available = -next_delay;
    if (per_cmd >= 0 && per_cmd < 1000)
	ms_per_cmd = per_cmd;
}

void
set_script_file(char * fn)
{
    if (script_fd) { fclose(script_fd); script_fd = 0; }
    ms_available = 0;
    gettimeofday(&last_script_tick, 0);

    script_fd = fopen(fn, "r");
    if (!script_fd)
	perror("Cannot open file");
    printf("Script started\n");
}

int
script_ticker(int socket_desc)
{
    if (!script_fd) return 0;

    struct timeval tv;
    gettimeofday(&tv, 0);
    int msec = (tv.tv_sec - last_script_tick.tv_sec)*1000 + (tv.tv_usec - last_script_tick.tv_usec)/1000;
    if (msec == 0) return ms_available >= 0;
    last_script_tick = tv;

    ms_available += msec;
    while(ms_available > ms_per_cmd) {
	char cmdbuf[1024];
	if (fgets(cmdbuf, sizeof(cmdbuf), script_fd) == 0) {
	    fclose(script_fd);
	    script_fd = 0;
	    printf("Script ended\n");
	    posn = spawn;
	    send_pkt_move(socket_desc, posn);
	    return 0;
	}
	char * s = strchr(cmdbuf, '\n');
	if (s) *s = 0;
	process_user_message(socket_desc, cmdbuf);
	ms_available -= ms_per_cmd;
    }

    return ms_available >= 0;
}
