#ifndef MEDDLY_C_H
#define MEDDLY_C_H

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Error codes                                                          */
/* ------------------------------------------------------------------ */
#define MEDDLY_C_OK          0
#define MEDDLY_C_ERR_NULL    1
#define MEDDLY_C_ERR_EXCEPT  2
#define MEDDLY_C_ERR_INVALID 3

/* ------------------------------------------------------------------ */
/* Forest kind (must match constants in src/types.jl)                  */
/* ------------------------------------------------------------------ */
#define MEDDLY_FOREST_MDD 0  /* not a relation */
#define MEDDLY_FOREST_MXD 1  /* relation */

/* ------------------------------------------------------------------ */
/* Forest range (must match constants in src/types.jl)                 */
/* ------------------------------------------------------------------ */
#define MEDDLY_RANGE_BOOLEAN 0
#define MEDDLY_RANGE_INTEGER 1

/* ------------------------------------------------------------------ */
/* Forest edge labeling (must match constants in src/types.jl)         */
/* ------------------------------------------------------------------ */
#define MEDDLY_EV_MULTI_TERMINAL 0  /* standard MT-MDD / MT-MDD */
#define MEDDLY_EV_PLUS           1  /* EV+MDD  (edge values summed) */
#define MEDDLY_EV_TIMES          2  /* EV×MDD  (edge values multiplied) */

/* ------------------------------------------------------------------ */
/* Error reporting                                                      */
/* ------------------------------------------------------------------ */
const char* meddly_last_error(void);

/* ------------------------------------------------------------------ */
/* Library lifecycle                                                    */
/* ------------------------------------------------------------------ */
int meddly_initialize(void);
int meddly_cleanup(void);

/* ------------------------------------------------------------------ */
/* Domain                                                               */
/* ------------------------------------------------------------------ */

/* sizes[i] = number of values for variable i+1 (bottom-up, 0-indexed) */
void* meddly_domain_create(const int* sizes, int num_levels);
int   meddly_domain_destroy(void* domain);

/* ------------------------------------------------------------------ */
/* Forest                                                               */
/* ------------------------------------------------------------------ */

/* Create forest with MULTI_TERMINAL edge labeling (original API). */
void* meddly_forest_create(void* domain, int kind, int range);

/* Create forest with explicit edge labeling (ev = MEDDLY_EV_*). */
void* meddly_forest_create_ev(void* domain, int kind, int range, int ev);

int   meddly_forest_destroy(void* forest);

/* ------------------------------------------------------------------ */
/* Edge                                                                 */
/* ------------------------------------------------------------------ */

/* Create edge initialized to empty set (false terminal) */
void* meddly_edge_create(void* forest);

/* Create edge representing the single minterm given by values[].
 * values[i] = assignment for variable i+1 (count == num_variables).
 * Slot 0 in the MEDDLY internal representation is filled automatically. */
void* meddly_edge_create_from_values(void* forest, const int* values, int count);

int meddly_edge_destroy(void* edge);

/* ------------------------------------------------------------------ */
/* Set operations — caller owns the returned edge (call destroy later) */
/* ------------------------------------------------------------------ */
int meddly_edge_union(void* a, void* b, void** result);
int meddly_edge_intersection(void* a, void* b, void** result);
int meddly_edge_difference(void* a, void* b, void** result);

/* ------------------------------------------------------------------ */
/* Integer edge creation                                                */
/* ------------------------------------------------------------------ */

/* Constant integer-valued edge: all variable assignments map to value. */
void* meddly_edge_create_constant_int(void* forest, long value);

/* Single-minterm integer edge: vars[i] = assignment for variable i+1.
 * Returns `value` at this minterm and 0 everywhere else. */
void* meddly_edge_create_from_minterm_int(void* forest, const int* vars,
                                           long value, int count);

/* ------------------------------------------------------------------ */
/* Generic binary apply — op_id must be one of MEDDLY_OP_*            */
/* ------------------------------------------------------------------ */
#define MEDDLY_OP_PLUS               10
#define MEDDLY_OP_MINUS              11
#define MEDDLY_OP_MULTIPLY           12
#define MEDDLY_OP_MAXIMUM            13
#define MEDDLY_OP_MINIMUM            14

#define MEDDLY_OP_EQUAL              15
#define MEDDLY_OP_NOT_EQUAL          16
#define MEDDLY_OP_LESS_THAN          17
#define MEDDLY_OP_LESS_THAN_EQUAL    18
#define MEDDLY_OP_GREATER_THAN       19
#define MEDDLY_OP_GREATER_THAN_EQUAL 20

/* Arithmetic binary ops: result placed in the same forest as operands. */
int meddly_edge_apply_binary(int op_id, void* a, void* b, void** result);

/* Comparison binary ops: result placed in result_forest (may differ from
 * operand forest, e.g. integer operands → boolean result forest). */
int meddly_edge_apply_binary_rf(int op_id, void* a, void* b,
                                 void* result_forest, void** result);

/* Copy an edge into a different forest with the same domain.
 * Primary use: convert a boolean-forest edge to an integer-forest edge (false→0, true→1). */
int meddly_edge_copy(void* src_edge, void* dst_forest, void** result);

/* ------------------------------------------------------------------ */
/* Logical complement (boolean forests only)                            */
/* ------------------------------------------------------------------ */
int meddly_edge_complement(void* a, void** result);

/* ------------------------------------------------------------------ */
/* DOT output                                                           */
/* ------------------------------------------------------------------ */

/* Write a Graphviz DOT file for the given edge.
 * basename: path prefix — the file written will be  basename + ".dot".
 * Returns MEDDLY_C_OK on success. */
int meddly_edge_todot(void* edge, const char* basename);

/* ------------------------------------------------------------------ */
/* Queries                                                              */
/* ------------------------------------------------------------------ */
double meddly_edge_cardinality(void* edge);
int    meddly_edge_is_empty(void* edge);   /* returns 1 if empty */

#ifdef __cplusplus
}
#endif

#endif /* MEDDLY_C_H */
