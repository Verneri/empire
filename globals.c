#include "extern.h"
int SMOOTH;        /* number of times to smooth map */
int WATER_RATIO;   /* percentage of map that is water */
int MIN_CITY_DIST; /* cities must be at least this far apart */
int delay_time;
int save_interval; /* turns between autosaves */

real_map_t map[MAP_SIZE];      /* the way the world really looks */
view_map_t comp_map[MAP_SIZE]; /* computer's view of the world */
view_map_t user_map[MAP_SIZE]; /* user's view of the world */

city_info_t city[NUM_CITY]; /* city information */

/*
There is one array to hold all allocated objects no matter who
owns them.  Objects are allocated from the array and placed on
a list corresponding to the type of object and its owner.
*/

piece_info_t *free_list;             /* index to free items in object list */
piece_info_t *user_obj[NUM_OBJECTS]; /* indices to user lists */
piece_info_t *comp_obj[NUM_OBJECTS]; /* indices to computer lists */
piece_info_t object[LIST_SIZE];      /* object list */

/* Display information. */
int lines; /* lines on screen */
int cols;  /* columns on screen */

/* miscellaneous */
long date;            /* number of game turns played */
bool automove;        /* true iff user is in automove mode */
bool resigned;        /* true iff computer resigned */
bool debug;           /* true iff in debugging mode */
bool print_debug;     /* true iff we print debugging stuff */
char print_vmap;      /* the map-printing mode */
bool trace_pmap;      /* true if we are tracing pmaps */
int win;              /* set when game is over - not a bool */
char jnkbuf[STRSIZE]; /* general purpose temporary buffer */
bool save_movie;      /* true iff we should save movie screens */
int user_score;       /* "score" for user and computer */
int comp_score;
char *savefile;