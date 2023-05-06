#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <math.h>

/*
 * TODO: Between timestamps.
 *       If it's before TS1 place the new in the old array
 *       If it's between them place the new in the new array.
 *       If it's after TS2 place the old in the new array.
 *
 * TODO: Change to pointers as size fields stick at max values?
 *       (but overflows are very possible)
 */

/*
 * Newest: Get the newest known block Id
 * Oldest: Get the oldest known block Id
 * deleteblocks: Set all blocks that have been modified to Air.
 */

FILE * ofd;

int do_file(FILE *);
int do_file_1(FILE *);
int do_file_2(FILE *);

typedef struct sort_chunk_t sort_chunk_t;
struct sort_chunk_t {
    uint32_t sequence;
    int32_t PlayerID;
    int32_t Timestamp;
    uint32_t Index;
    uint16_t Type;
    uint16_t OldBlock;
    uint16_t NewBlock;
};

uint16_t * block_array = 0;
uint16_t * old_block_array = 0;
uintptr_t block_array_size = 0;

void process_day(sort_chunk_t * chunk_list, int chunk_list_ptr);

static enum { newest = 0, oldest = 1, deleteblocks = 2, filtered_new = 3, allblocks = 4,
	perday = 5, last_order = 6, last_scan = 7
    } method = newest;
int guest = 0;

char physics_visual[256] = {
  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
 64, 65,  0,  0,  0,  0, 39, 36, 36, 10, 46, 21, 22, 22, 22, 22,
  4,  0, 22, 21,  0, 22, 23, 24, 22, 26, 27, 28, 30, 31, 32, 33,
 34, 35, 36, 22, 20, 49, 45,  1,  4,  0,  9, 11,  4, 19,  5, 17,
 10, 49, 20,  1, 18, 12,  5, 25, 46, 44, 17, 49, 20,  1, 18, 12,
  5, 25, 36, 34,  0,  9, 11, 46, 44,  0,  9, 11,  8, 10, 22, 27,
 22,  8, 10, 28, 17, 49, 20,  1, 18, 12,  5, 25, 46, 44, 11,  9,
  0,  9, 11, 22,  0,  0,  9, 11,  0,  0,  0,  0,  0,  0,  0, 28,
 22, 21, 11,  0,  0,  0, 46, 46, 10, 10, 46, 20, 41, 42, 11,  9,
  0,  8, 10, 10,  8,  0, 22, 22,  0,  0,  0,  0,  0,  0,  0,  0,
  0,  0,  0, 21, 10,  0,  0,  0,  0,  0, 22, 22, 42,  3,  2, 29,
 47,  0,  0,  0,  0,  0, 27, 46, 48, 24, 22, 36, 34,  8, 10, 21,
 29, 22, 10, 22, 22, 41, 19, 35, 21, 29, 49, 34, 16, 41,  0, 22
};

void main(int argc, char **argv)
{
    char * filename = 0;
    ofd = stdout;

    while(argc>1 && argv[1][0] == '-') {
	argv++; argc--;
	if (argv[0][1] == '-' && argv[0][2] == 0)
	    break;

	if (strcmp(argv[0], "-O") == 0) { method = oldest; continue; }
	if (strcmp(argv[0], "-n") == 0) { method = last_order; continue; }
	if (strcmp(argv[0], "-N") == 0) { method = newest; continue; }
	if (strcmp(argv[0], "-NN") == 0) { method = filtered_new; continue; }
	if (strcmp(argv[0], "-D") == 0) { method = deleteblocks; continue; }
	if (strcmp(argv[0], "-A") == 0) { method = allblocks; continue; }
	if (strcmp(argv[0], "-g") == 0) { guest = 1; continue; }
	if (strcmp(argv[0], "-y") == 0) { method = perday; continue; }
	fprintf(stderr, "Unknown option %s\n", argv[0]);
	exit(1);
    }
    if (argc>1) filename = argv[1];

    if (filename) {
	FILE * ifd = fopen(filename, "r");
	if (!ifd) {fprintf(stderr, "Cannot open file '%s'\n", filename); exit(1);}
	if (!do_file(ifd))
	    fprintf(stderr, "File decoding failed\n");
	fclose(ifd);
    } else
	do_file(stdin);
}

#define UIntLE16(x) (*(uint8_t*)(x) + *(uint8_t*)((x)+1)*256)
#define IntLE32(x)  (*(uint8_t*)(x) + (*(uint8_t*)((x)+1)<<8) + \
		    (*(uint8_t*)((x)+2)<<16) + (*(uint8_t*)((x)+3)<<24))
#define UIntLE32(x) ((uint32_t)*(uint8_t*)(x) + \
		    ((uint32_t)*(uint8_t*)((x)+1)<<8) + \
		    ((uint32_t)*(uint8_t*)((x)+2)<<16) + \
		    ((uint32_t)*(uint8_t*)((x)+3)<<24))

#define MAX_COUNT 1024
#define PHYSICS_OFFSET (MAX_COUNT-256)
#define CHUNK_SZ 16

int
do_file(FILE * ifd)
{
    if (method == perday)
	return do_file_2(ifd);

    if (method == last_order) {
	method = last_scan;
	do_file_1(ifd);
	method = last_order;
	rewind(ifd);
    }
    return do_file_1(ifd);
}

int
do_file_1(FILE * ifd)
{
    uint8_t chunk_buf[CHUNK_SZ];
    if (fread(chunk_buf, sizeof(chunk_buf), 1, ifd) <= 0 ||
	    strncmp("CBDB_MCG\001", chunk_buf, 10)) {

	fprintf(stderr, "Incorrect magic number\n");
	return 0;
    }

    int cells_x = UIntLE16(chunk_buf+10),
	cells_y = UIntLE16(chunk_buf+12),
	cells_z = UIntLE16(chunk_buf+14);

    if (cells_x > 16384 || cells_y > 16384 || cells_z > 16384) {
	fprintf(stderr, "Array size (%d,%d,%d)\n", cells_x, cells_y, cells_z);
	return 0;
    }

    if (method != allblocks && method != last_order) {
	if (!(block_array=calloc(cells_x*cells_y, cells_z*sizeof(*block_array)))) {
	    fprintf(stderr, "Memory allocation failed\n");
	    return -1;
	}

	block_array_size = (uintptr_t)cells_x*cells_y*cells_z;
	memset(block_array, 0xFF, sizeof*block_array*block_array_size);
    }

    if (method == filtered_new) {
	if (!(old_block_array=calloc(cells_x*cells_y, cells_z*sizeof(*block_array)))) {
	    fprintf(stderr, "Memory allocation failed\n");
	    return -1;
	}

	memset(old_block_array, 0xFF, sizeof*old_block_array*block_array_size);
    }


    int last_player = -1;
    int last_day = -1;
    printf("# Reading chunks (%d,%d,%d)\n", cells_x, cells_y, cells_z);
    while (fread(chunk_buf, sizeof(chunk_buf), 1, ifd) == 1)
    {
	// 0/4  PlayerID
	// 4/4  Timestamp seconds since 2010-01-01T00:00:00+0000
	// 8/4  Index = (y * cells_z + z) * cells_x + x;
	// 12   Old block 8bit
	// 13   New block 8bit
	// 14   Bits type of update
	// 15   0..3 Bits update type, 4..7 Block high bits

	int32_t PlayerID = IntLE32(chunk_buf);
	int32_t Timestamp = IntLE32(chunk_buf+4); // Signed?
	uint32_t Index = UIntLE32(chunk_buf+8);
	time_t unix_ts = (time_t)1262304000 + Timestamp;
	int Type = UIntLE16(chunk_buf+14) & 0xFFF;

	int OldBlock = chunk_buf[12];
	OldBlock |= ((chunk_buf[15]&0x40)<<2);
	OldBlock |= ((chunk_buf[15]&0x10)<<5);
	if (method == allblocks || method == last_order || method == last_scan) {
	    if (OldBlock >= 66 && OldBlock < 256 ) OldBlock += PHYSICS_OFFSET;
	    else if (OldBlock >= 256) OldBlock -= 256;
	} else {
	    if (OldBlock >= 66 && OldBlock < 256 ) OldBlock = physics_visual[OldBlock];
	    else if (OldBlock >= 256) OldBlock -= 256;
	}
	if (guest) {
	    if (OldBlock == 7) OldBlock = 49;
	    else if (OldBlock == 8 || OldBlock == 10 ) OldBlock++;
	}

	int NewBlock = chunk_buf[13];
	NewBlock |= ((chunk_buf[15]&0x80)<<1);
	NewBlock |= ((chunk_buf[15]&0x20)<<4);
	if (NewBlock >= 66 && NewBlock < 256 ) NewBlock += PHYSICS_OFFSET;
	else if (NewBlock >= 256) NewBlock -= 256;

#if 1
	if (!(method == allblocks || method == last_order || method == last_scan)) {
	    if (NewBlock >= PHYSICS_OFFSET && NewBlock < MAX_COUNT)
		NewBlock = physics_visual[NewBlock & 0xFF];
	}
	if (guest) {
	    if (NewBlock == 7) NewBlock = 49;
	    else if (NewBlock == 8 || NewBlock == 10 ) NewBlock++;
	}
#endif

	// if (NewBlock == 54) NewBlock = OldBlock;
	// if (NewBlock == 54) continue;
	// if (NewBlock>767 || OldBlock>767) continue;

	// if (PlayerID == 1) continue;
	// if (PlayerID == 12) continue;
	// if (PlayerID == 55) continue;
	// if (PlayerID == 202) continue;
	// if (PlayerID == 242) continue;
	// if (PlayerID == 417) continue;
	// if (PlayerID == 16777215) continue;

	if (method != allblocks && Index >= block_array_size) continue;

	if (method == oldest) {
	    if (block_array[Index] < MAX_COUNT) continue;
	    block_array[Index] = OldBlock;
	} else if (method == newest || method == last_scan) {
	    block_array[Index] = NewBlock;
	} else if (method == deleteblocks) {
	    block_array[Index] = 0;
	} else if (method == filtered_new) {
	    if (old_block_array[Index] >= MAX_COUNT)
		old_block_array[Index] = OldBlock;

	    if (old_block_array[Index] == NewBlock)
		block_array[Index] = -1;
	    else
		block_array[Index] = NewBlock;
	} else if (method == allblocks) {
	    if (PlayerID != last_player || last_day != unix_ts/86400) {
		printf("# Player %d at %s", PlayerID, ctime(&unix_ts));
		last_player = PlayerID;
		last_day = unix_ts/86400;
	    }
	    int x, y, z;
	    x = Index % cells_x; Index = Index / cells_x;
	    z = Index % cells_z; Index = Index / cells_z;
	    y = Index;

	    char * wname = "";
	    char wbuf[16];

	    if (OldBlock == NewBlock)
		wname = "NOP";
	    else if ((Type & (1<<0)) != 0) {
		if (NewBlock == 0) wname = "Deleted";
		else wname = "Placed";
	    }
            else if ((Type & (1<<1)) != 0) wname = "Painted";
	    else if ((Type & (1<<2)) != 0) wname = "Drawn";
	    else if ((Type & (1<<3)) != 0) wname = "Replaced";
	    else if ((Type & (1<<4)) != 0) wname = "Pasted";
	    else if ((Type & (1<<5)) != 0) wname = "Cut";
	    else if ((Type & (1<<6)) != 0) wname = "Filled";
	    else if ((Type & (1<<7)) != 0) wname = "Restored";
	    else if ((Type & (1<<8)) != 0) wname = "UndoneOther";
	    else if ((Type & (1<<9)) != 0) wname = "UndoneSelf";
	    else if ((Type & (1<<10)) != 0) wname = "RedoneSelf";
	    else if ((Type & (1<<11)) != 0) wname = "FixGrass";
	    else sprintf(wname = wbuf, "#%03x", Type);

	    if (NewBlock >= PHYSICS_OFFSET)
		printf("/pl @%d %d %d %d # was %d, %s\n",
		    NewBlock, x, y, z, OldBlock, wname);
	    else
		printf("/pl %d %d %d %d # was %d, %s\n",
		    NewBlock, x, y, z, OldBlock, wname);
	} else if (method == last_order) {
	    if (block_array[Index] == NewBlock)
	    {
		block_array[Index] = -1;

		int x, y, z;
		x = Index % cells_x; Index = Index / cells_x;
		z = Index % cells_z; Index = Index / cells_z;
		y = Index;

		if (NewBlock >= PHYSICS_OFFSET)
		    printf("/pl @%d %d %d %d\n", NewBlock, x, y, z);
		else
		    printf("/pl %d %d %d %d\n", NewBlock, x, y, z);
	    }
	}
    }

    if (method != allblocks && method != last_order && method != last_scan)
	for(int y=0; y<cells_y; y++)
	    for(int z=0; z<cells_z; z++)
		for(int x=0; x<cells_x; x++)
		{
		    int Index = (y * cells_z + z) * cells_x + x;
		    if (block_array[Index] >= MAX_COUNT) continue;
		    printf("/pl %d %d %d %d\n", block_array[Index], x, y, z);
		}

    return 1;
}

int
do_file_2(FILE * ifd)
{
    uint8_t chunk_buf[CHUNK_SZ];
    if (fread(chunk_buf, sizeof(chunk_buf), 1, ifd) <= 0 ||
            strncmp("CBDB_MCG\001", chunk_buf, 10)) {

        fprintf(stderr, "Incorrect magic number\n");
        return 0;
    }

    int cells_x = UIntLE16(chunk_buf+10),
        cells_y = UIntLE16(chunk_buf+12),
        cells_z = UIntLE16(chunk_buf+14);

    if (cells_x > 16384 || cells_y > 16384 || cells_z > 16384) {
        fprintf(stderr, "Array size (%d,%d,%d)\n", cells_x, cells_y, cells_z);
        return 0;
    }

    if (!(block_array=calloc(cells_x*cells_y, cells_z*sizeof(*block_array)))) {
	fprintf(stderr, "Memory allocation failed\n");
	return -1;
    }

    block_array_size = (uintptr_t)cells_x*cells_y*cells_z;
    memset(block_array, 0xFF, sizeof*block_array*block_array_size);

    fwrite(chunk_buf, sizeof(chunk_buf), 1, ofd);

    int unix_day = 0;
    int chunk_list_ptr = 0;
    int chunk_list_sz = 0;
    sort_chunk_t * chunk_list = 0;

    fprintf(stderr, "# Reading chunks (%d,%d,%d)\n", cells_x, cells_y, cells_z);
    while (fread(chunk_buf, sizeof(chunk_buf), 1, ifd) == 1)
    {
        // 0/4  PlayerID
        // 4/4  Timestamp seconds since 2010-01-01T00:00:00+0000
        // 8/4  Index = (y * cells_z + z) * cells_x + x;
        // 12   Old block 8bit
        // 13   New block 8bit
        // 14   Bits type of update
        // 15   0..3 Bits update type, 4..7 Block high bits

        int32_t PlayerID = IntLE32(chunk_buf);
        int32_t Timestamp = IntLE32(chunk_buf+4); // Signed?
        uint32_t Index = UIntLE32(chunk_buf+8);
        time_t unix_ts = (time_t)1262304000 + Timestamp;
        int Type = UIntLE16(chunk_buf+14) & 0xFFF;

        int OldBlock = chunk_buf[12];
        OldBlock |= ((chunk_buf[15]&0x40)<<2);
        OldBlock |= ((chunk_buf[15]&0x10)<<5);

        int NewBlock = chunk_buf[13];
        NewBlock |= ((chunk_buf[15]&0x80)<<1);
        NewBlock |= ((chunk_buf[15]&0x20)<<4);

	if (unix_ts/86400 != unix_day && chunk_list_ptr > 0) {
	    process_day(chunk_list, chunk_list_ptr);
	    chunk_list_ptr = 0;
	}

	unix_day = unix_ts/86400;

	if (chunk_list_ptr +2 > chunk_list_sz) {
	    int sz = chunk_list_sz?chunk_list_sz*2:1024;
	    sort_chunk_t * p = realloc(chunk_list, sz * sizeof(sort_chunk_t));
	    if (p) {
		chunk_list = p;
                chunk_list_sz = sz;
	    }
	}

	sort_chunk_t n = {0};
	n.sequence = chunk_list_ptr;
	n.PlayerID = PlayerID;
	n.Timestamp = Timestamp;
	n.Index = Index;
	n.Type = Type;
	n.OldBlock = OldBlock;
	n.NewBlock = NewBlock;

	memcpy(chunk_list+chunk_list_ptr, &n, sizeof(sort_chunk_t));
	chunk_list_ptr++;
    }

    if (chunk_list_ptr>0)
	process_day(chunk_list, chunk_list_ptr);

    if (chunk_list) free(chunk_list);
    chunk_list = 0;

    return 1;
}

static int
orderchunk(const void *p1, const void *p2)
{
    sort_chunk_t *e1 = (sort_chunk_t  *)p1;
    sort_chunk_t *e2 = (sort_chunk_t  *)p2;

    // return (int)(e1->order - e2->order);

    if (e1->Index > e2->Index) return 1;
    if (e1->Index < e2->Index) return -1;

    // Make stable sort
    if (e1->sequence > e2->sequence) return 1;
    if (e1->sequence < e2->sequence) return -1;
    return 0;
}

void
process_day(sort_chunk_t * chunk_list, int chunk_list_cnt)
{
    qsort(chunk_list, chunk_list_cnt, sizeof(*chunk_list), orderchunk);

    uint8_t chunk_buf[CHUNK_SZ] = {0};
    sort_chunk_t curr_chunk = {0};
    /*
	for each index output one chunk.
	Merge PlayerID -- if different use nil
        Timestamp  to midnight
        Index unchanged
        Type = 1
        OldBlock from first
        NewBlock from last
    */

#define SetIntLE32(p, v) \
    ((p)[0] = ((v) )), \
    ((p)[1] = ((v) >> 8)), \
    ((p)[2] = ((v) >> 16)), \
    ((p)[3] = ((v) >> 24))

    int j = 0, i;
    for(i=0; i<chunk_list_cnt; i++)
    {
	if (j==i) {
	    curr_chunk = chunk_list[i];
	    curr_chunk.Timestamp = chunk_list[i].Timestamp/86400*86400;
	    curr_chunk.Type = 1;

	    // If we know the old block, preserve it.
	    if (block_array[curr_chunk.Index] != 0xFFFF)
		curr_chunk.OldBlock = block_array[curr_chunk.Index];
	} else {
	    if (chunk_list[i].PlayerID != chunk_list[j].PlayerID) {
		curr_chunk.PlayerID = 0xFFFFFF; // (console)
	    }
	    // Set new block.
	    curr_chunk.NewBlock = chunk_list[i].NewBlock;
	}

	if (i+1>= chunk_list_cnt || chunk_list[i+1].Index != chunk_list[j].Index) {
	    // Humm, first update is a NOP ? Let's not remove it.
	    if (curr_chunk.NewBlock == curr_chunk.OldBlock && block_array[curr_chunk.Index] == 0xFFFF)
		curr_chunk.OldBlock = !curr_chunk.OldBlock;

	    block_array[curr_chunk.Index] = curr_chunk.NewBlock;

	    if (curr_chunk.OldBlock != curr_chunk.NewBlock) {
		SetIntLE32(chunk_buf+0, curr_chunk.PlayerID);
		SetIntLE32(chunk_buf+4, curr_chunk.Timestamp);
		SetIntLE32(chunk_buf+8, curr_chunk.Index);
		chunk_buf[12] = curr_chunk.OldBlock;
		chunk_buf[13] = curr_chunk.NewBlock;
		chunk_buf[14] = curr_chunk.Type;
		chunk_buf[15] =
		    (((curr_chunk.Type >> 8)&0xF)) +
		    (((curr_chunk.OldBlock >> 8)&1) << 6) +
		    (((curr_chunk.OldBlock >> 9)&1) << 4) +
		    (((curr_chunk.NewBlock >> 8)&1) << 7) +
		    (((curr_chunk.NewBlock >> 9)&1) << 5) ;
		fwrite(chunk_buf, sizeof(chunk_buf), 1, ofd);
	    }
	    j = i+1;
	}
    }
}
