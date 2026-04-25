/*
 * meddly_c.cpp — C ABI shim for MEDDLY 0.18.x.
 *
 * API differences from earlier MEDDLY versions:
 *   - Header:  #include <meddly/meddly.h>  (installed under a subdirectory)
 *   - Domain:  domain::createBottomUp() / domain::destroy()  (static)
 *   - Forest:  forest::create() / forest::destroy()          (static)
 *   - set_or_rel is a bool alias; use MEDDLY::SET / MEDDLY::RELATION
 *   - range_type and edge_labeling are scoped enums
 *   - Empty edge: forest::createConstant(false, dd_edge&)
 *   - Single minterm: MEDDLY::minterm class + buildFunction()
 *   - Operations: MEDDLY::apply(MEDDLY::UNION, a, b, c) unchanged
 *   - Cardinality: MEDDLY::apply(MEDDLY::CARDINALITY, e, double&)
 */

#include "meddly_c.h"
#include <meddly/meddly.h>
#include <meddly/io_dot.h>
#include <cstring>
#include <stdexcept>

/* ------------------------------------------------------------------ */
static char g_last_error[1024] = "no error";

static void set_error(const char* msg) {
    std::strncpy(g_last_error, msg, sizeof(g_last_error) - 1);
    g_last_error[sizeof(g_last_error) - 1] = '\0';
}

/* ------------------------------------------------------------------ */
extern "C" {
/* ------------------------------------------------------------------ */

const char* meddly_last_error(void) { return g_last_error; }

/* ------------------------------------------------------------------ */
/* Library lifecycle                                                    */
/* ------------------------------------------------------------------ */

int meddly_initialize(void) {
    try {
        MEDDLY::initialize();
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_initialize"); }
    return MEDDLY_C_ERR_EXCEPT;
}

int meddly_cleanup(void) {
    try {
        MEDDLY::cleanup();
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_cleanup"); }
    return MEDDLY_C_ERR_EXCEPT;
}

/* ------------------------------------------------------------------ */
/* Domain                                                               */
/* ------------------------------------------------------------------ */

void* meddly_domain_create(const int* sizes, int num_levels) {
    if (!sizes || num_levels <= 0) {
        set_error("meddly_domain_create: invalid arguments");
        return nullptr;
    }
    try {
        int* bounds = new int[num_levels];
        for (int i = 0; i < num_levels; i++) bounds[i] = sizes[i];
        MEDDLY::domain* d = MEDDLY::domain::createBottomUp(
            bounds, static_cast<unsigned>(num_levels));
        delete[] bounds;
        if (!d) { set_error("domain::createBottomUp returned null"); return nullptr; }
        return static_cast<void*>(d);
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_domain_create"); }
    return nullptr;
}

int meddly_domain_destroy(void* domain) {
    if (!domain) { set_error("meddly_domain_destroy: null"); return MEDDLY_C_ERR_NULL; }
    try {
        MEDDLY::domain* d = static_cast<MEDDLY::domain*>(domain);
        MEDDLY::domain::destroy(d);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_domain_destroy"); }
    return MEDDLY_C_ERR_EXCEPT;
}

/* ------------------------------------------------------------------ */
/* Forest                                                               */
/* ------------------------------------------------------------------ */

void* meddly_forest_create(void* domain, int kind, int range) {
    if (!domain) { set_error("meddly_forest_create: null domain"); return nullptr; }
    try {
        MEDDLY::domain* d = static_cast<MEDDLY::domain*>(domain);

        MEDDLY::set_or_rel sr =
            (kind == MEDDLY_FOREST_MXD) ? MEDDLY::RELATION : MEDDLY::SET;

        MEDDLY::range_type rt = (range == MEDDLY_RANGE_BOOLEAN)
            ? MEDDLY::range_type::BOOLEAN
            : MEDDLY::range_type::INTEGER;

        MEDDLY::forest* f = MEDDLY::forest::create(
            d, sr, rt, MEDDLY::edge_labeling::MULTI_TERMINAL);
        if (!f) { set_error("forest::create returned null"); return nullptr; }
        return static_cast<void*>(f);
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_forest_create"); }
    return nullptr;
}

void* meddly_forest_create_ev(void* domain, int kind, int range, int ev) {
    if (!domain) { set_error("meddly_forest_create_ev: null domain"); return nullptr; }
    try {
        MEDDLY::domain* d = static_cast<MEDDLY::domain*>(domain);

        MEDDLY::set_or_rel sr =
            (kind == MEDDLY_FOREST_MXD) ? MEDDLY::RELATION : MEDDLY::SET;

        MEDDLY::range_type rt = (range == MEDDLY_RANGE_BOOLEAN)
            ? MEDDLY::range_type::BOOLEAN
            : MEDDLY::range_type::INTEGER;

        MEDDLY::edge_labeling el;
        switch (ev) {
            case MEDDLY_EV_PLUS:  el = MEDDLY::edge_labeling::EVPLUS;  break;
            case MEDDLY_EV_TIMES: el = MEDDLY::edge_labeling::EVTIMES; break;
            default:              el = MEDDLY::edge_labeling::MULTI_TERMINAL; break;
        }

        MEDDLY::forest* f = MEDDLY::forest::create(d, sr, rt, el);
        if (!f) { set_error("forest::create returned null"); return nullptr; }
        return static_cast<void*>(f);
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_forest_create_ev"); }
    return nullptr;
}

int meddly_forest_destroy(void* forest) {
    if (!forest) { set_error("meddly_forest_destroy: null"); return MEDDLY_C_ERR_NULL; }
    try {
        MEDDLY::forest* f = static_cast<MEDDLY::forest*>(forest);
        MEDDLY::forest::destroy(f);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_forest_destroy"); }
    return MEDDLY_C_ERR_EXCEPT;
}

/* ------------------------------------------------------------------ */
/* Edge helpers                                                         */
/* ------------------------------------------------------------------ */

static inline MEDDLY::forest* edge_forest(void* edge) {
    return static_cast<MEDDLY::dd_edge*>(edge)->getForest();
}

/* ------------------------------------------------------------------ */
/* Edge                                                                 */
/* ------------------------------------------------------------------ */

void* meddly_edge_create(void* forest) {
    if (!forest) { set_error("meddly_edge_create: null forest"); return nullptr; }
    try {
        MEDDLY::forest* f = static_cast<MEDDLY::forest*>(forest);
        MEDDLY::dd_edge* e = new MEDDLY::dd_edge(f);
        // node = 0 by default: false terminal for MT-boolean, integer-0 for MT-integer,
        // OMEGA_INFINITY (absent) for EV+MDD — all represent the "empty/zero" function.
        // No explicit createConstant call needed.
        return static_cast<void*>(e);
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_create"); }
    return nullptr;
}

void* meddly_edge_create_from_values(void* forest, const int* values, int count) {
    if (!forest || !values || count <= 0) {
        set_error("meddly_edge_create_from_values: invalid arguments");
        return nullptr;
    }
    try {
        MEDDLY::forest* f = static_cast<MEDDLY::forest*>(forest);
        MEDDLY::dd_edge* e = new MEDDLY::dd_edge(f);

        // Build the characteristic function of a single element.
        // values[i] (C 0-indexed) = assignment for MEDDLY variable i+1 (1-indexed).
        MEDDLY::minterm m(f);
        m.setValue(true);               // this point IS in the set
        for (int i = 0; i < count; i++)
            m.setVar(i + 1, values[i]);
        m.buildFunction(false, *e);     // false everywhere else
        return static_cast<void*>(e);
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& ex) { set_error(ex.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_create_from_values"); }
    return nullptr;
}

int meddly_edge_destroy(void* edge) {
    if (!edge) return MEDDLY_C_OK;
    delete static_cast<MEDDLY::dd_edge*>(edge);
    return MEDDLY_C_OK;
}

/* ------------------------------------------------------------------ */
/* Integer edge creation                                                */
/* ------------------------------------------------------------------ */

void* meddly_edge_create_constant_int(void* forest, long value) {
    if (!forest) { set_error("meddly_edge_create_constant_int: null forest"); return nullptr; }
    try {
        MEDDLY::forest* f = static_cast<MEDDLY::forest*>(forest);
        MEDDLY::dd_edge* e = new MEDDLY::dd_edge(f);
        f->createConstant(MEDDLY::rangeval(value), *e);
        return static_cast<void*>(e);
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_create_constant_int"); }
    return nullptr;
}

void* meddly_edge_create_from_minterm_int(void* forest, const int* vars,
                                           long value, int count) {
    if (!forest || !vars || count <= 0) {
        set_error("meddly_edge_create_from_minterm_int: invalid arguments");
        return nullptr;
    }
    try {
        MEDDLY::forest* f = static_cast<MEDDLY::forest*>(forest);
        MEDDLY::dd_edge* e = new MEDDLY::dd_edge(f);
        MEDDLY::minterm m(f);
        m.setValue(MEDDLY::rangeval(value));
        for (int i = 0; i < count; i++)
            m.setVar(i + 1, vars[i]);
        // For EV+MDD, use +∞ background so non-specified minterms are absent
        // (OMEGA_INFINITY), giving cardinality = 1 for a single-minterm edge.
        // For MT forests, use 0 as background (zero/false terminal).
        MEDDLY::rangeval bg;
        if (f->isEVPlus()) {
            bg = MEDDLY::rangeval(MEDDLY::range_special::PLUS_INFINITY,
                                  MEDDLY::range_type::INTEGER);
        } else {
            bg = MEDDLY::rangeval(0L);
        }
        m.buildFunction(bg, *e);
        return static_cast<void*>(e);
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& ex) { set_error(ex.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_create_from_minterm_int"); }
    return nullptr;
}

/* ------------------------------------------------------------------ */
/* Generic binary apply                                                 */
/* ------------------------------------------------------------------ */

int meddly_edge_apply_binary(int op_id, void* a, void* b, void** result) {
    if (!a || !b || !result) {
        set_error("meddly_edge_apply_binary: null argument"); return MEDDLY_C_ERR_NULL;
    }
    try {
        MEDDLY::dd_edge* ea = static_cast<MEDDLY::dd_edge*>(a);
        MEDDLY::dd_edge* eb = static_cast<MEDDLY::dd_edge*>(b);
        MEDDLY::dd_edge* ec = new MEDDLY::dd_edge(edge_forest(a));
        switch (op_id) {
            case MEDDLY_OP_PLUS:     MEDDLY::apply(MEDDLY::PLUS,     *ea, *eb, *ec); break;
            case MEDDLY_OP_MINUS:    MEDDLY::apply(MEDDLY::MINUS,    *ea, *eb, *ec); break;
            case MEDDLY_OP_MULTIPLY: MEDDLY::apply(MEDDLY::MULTIPLY, *ea, *eb, *ec); break;
            case MEDDLY_OP_MAXIMUM:  MEDDLY::apply(MEDDLY::MAXIMUM,  *ea, *eb, *ec); break;
            case MEDDLY_OP_MINIMUM:  MEDDLY::apply(MEDDLY::MINIMUM,  *ea, *eb, *ec); break;
            default:
                delete ec;
                set_error("meddly_edge_apply_binary: unknown op_id");
                return MEDDLY_C_ERR_INVALID;
        }
        *result = static_cast<void*>(ec);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_apply_binary"); }
    return MEDDLY_C_ERR_EXCEPT;
}

int meddly_edge_apply_binary_rf(int op_id, void* a, void* b,
                                 void* result_forest, void** result) {
    if (!a || !b || !result_forest || !result) {
        set_error("meddly_edge_apply_binary_rf: null argument"); return MEDDLY_C_ERR_NULL;
    }
    try {
        MEDDLY::dd_edge* ea = static_cast<MEDDLY::dd_edge*>(a);
        MEDDLY::dd_edge* eb = static_cast<MEDDLY::dd_edge*>(b);
        MEDDLY::forest*  rf = static_cast<MEDDLY::forest*>(result_forest);
        MEDDLY::dd_edge* ec = new MEDDLY::dd_edge(rf);
        switch (op_id) {
            case MEDDLY_OP_EQUAL:              MEDDLY::apply(MEDDLY::EQUAL,              *ea, *eb, *ec); break;
            case MEDDLY_OP_NOT_EQUAL:          MEDDLY::apply(MEDDLY::NOT_EQUAL,          *ea, *eb, *ec); break;
            case MEDDLY_OP_LESS_THAN:          MEDDLY::apply(MEDDLY::LESS_THAN,          *ea, *eb, *ec); break;
            case MEDDLY_OP_LESS_THAN_EQUAL:    MEDDLY::apply(MEDDLY::LESS_THAN_EQUAL,    *ea, *eb, *ec); break;
            case MEDDLY_OP_GREATER_THAN:       MEDDLY::apply(MEDDLY::GREATER_THAN,       *ea, *eb, *ec); break;
            case MEDDLY_OP_GREATER_THAN_EQUAL: MEDDLY::apply(MEDDLY::GREATER_THAN_EQUAL, *ea, *eb, *ec); break;
            default:
                delete ec;
                set_error("meddly_edge_apply_binary_rf: unknown op_id");
                return MEDDLY_C_ERR_INVALID;
        }
        *result = static_cast<void*>(ec);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_apply_binary_rf"); }
    return MEDDLY_C_ERR_EXCEPT;
}

int meddly_edge_copy(void* src_edge, void* dst_forest, void** result) {
    if (!src_edge || !dst_forest || !result) {
        set_error("meddly_edge_copy: null argument"); return MEDDLY_C_ERR_NULL;
    }
    try {
        MEDDLY::dd_edge* src = static_cast<MEDDLY::dd_edge*>(src_edge);
        MEDDLY::forest*   df = static_cast<MEDDLY::forest*>(dst_forest);
        MEDDLY::dd_edge* dst = new MEDDLY::dd_edge(df);
        MEDDLY::apply(MEDDLY::COPY, *src, *dst);
        *result = static_cast<void*>(dst);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_copy"); }
    return MEDDLY_C_ERR_EXCEPT;
}

/* ------------------------------------------------------------------ */
/* Set operations                                                       */
/* ------------------------------------------------------------------ */

int meddly_edge_union(void* a, void* b, void** result) {
    if (!a || !b || !result) {
        set_error("meddly_edge_union: null argument"); return MEDDLY_C_ERR_NULL;
    }
    try {
        MEDDLY::dd_edge* ea = static_cast<MEDDLY::dd_edge*>(a);
        MEDDLY::dd_edge* eb = static_cast<MEDDLY::dd_edge*>(b);
        MEDDLY::dd_edge* ec = new MEDDLY::dd_edge(edge_forest(a));
        MEDDLY::apply(MEDDLY::UNION, *ea, *eb, *ec);
        *result = static_cast<void*>(ec);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_union"); }
    return MEDDLY_C_ERR_EXCEPT;
}

int meddly_edge_intersection(void* a, void* b, void** result) {
    if (!a || !b || !result) {
        set_error("meddly_edge_intersection: null argument"); return MEDDLY_C_ERR_NULL;
    }
    try {
        MEDDLY::dd_edge* ea = static_cast<MEDDLY::dd_edge*>(a);
        MEDDLY::dd_edge* eb = static_cast<MEDDLY::dd_edge*>(b);
        MEDDLY::dd_edge* ec = new MEDDLY::dd_edge(edge_forest(a));
        MEDDLY::apply(MEDDLY::INTERSECTION, *ea, *eb, *ec);
        *result = static_cast<void*>(ec);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_intersection"); }
    return MEDDLY_C_ERR_EXCEPT;
}

int meddly_edge_difference(void* a, void* b, void** result) {
    if (!a || !b || !result) {
        set_error("meddly_edge_difference: null argument"); return MEDDLY_C_ERR_NULL;
    }
    try {
        MEDDLY::dd_edge* ea = static_cast<MEDDLY::dd_edge*>(a);
        MEDDLY::dd_edge* eb = static_cast<MEDDLY::dd_edge*>(b);
        MEDDLY::dd_edge* ec = new MEDDLY::dd_edge(edge_forest(a));
        MEDDLY::apply(MEDDLY::DIFFERENCE, *ea, *eb, *ec);
        *result = static_cast<void*>(ec);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_difference"); }
    return MEDDLY_C_ERR_EXCEPT;
}

/* ------------------------------------------------------------------ */
/* Logical complement                                                   */
/* ------------------------------------------------------------------ */

int meddly_edge_complement(void* a, void** result) {
    if (!a || !result) { set_error("meddly_edge_complement: null argument"); return MEDDLY_C_ERR_NULL; }
    try {
        MEDDLY::dd_edge* ea = static_cast<MEDDLY::dd_edge*>(a);
        MEDDLY::dd_edge* ec = new MEDDLY::dd_edge(edge_forest(a));
        MEDDLY::apply(MEDDLY::COMPLEMENT, *ea, *ec);
        *result = static_cast<void*>(ec);
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_complement"); }
    return MEDDLY_C_ERR_EXCEPT;
}

/* ------------------------------------------------------------------ */
/* DOT output                                                           */
/* ------------------------------------------------------------------ */

int meddly_edge_todot(void* edge, const char* basename) {
    if (!edge || !basename) {
        set_error("meddly_edge_todot: null argument"); return MEDDLY_C_ERR_NULL;
    }
    try {
        MEDDLY::dd_edge* e = static_cast<MEDDLY::dd_edge*>(edge);
        MEDDLY::forest*  f = e->getForest();
        MEDDLY::dot_maker dm(f, basename);
        dm.addRootEdge(*e);
        dm.doneGraph();
        return MEDDLY_C_OK;
    } catch (const MEDDLY::error& e) { set_error(e.getName()); }
      catch (const std::exception& e) { set_error(e.what()); }
      catch (...) { set_error("unknown exception in meddly_edge_todot"); }
    return MEDDLY_C_ERR_EXCEPT;
}

/* ------------------------------------------------------------------ */
/* Queries                                                              */
/* ------------------------------------------------------------------ */

double meddly_edge_cardinality(void* edge) {
    if (!edge) return 0.0;
    try {
        MEDDLY::dd_edge* e = static_cast<MEDDLY::dd_edge*>(edge);
        double card = 0.0;
        MEDDLY::apply(MEDDLY::CARDINALITY, *e, card);
        return card;
    } catch (...) { return -1.0; }
}

int meddly_edge_is_empty(void* edge) {
    if (!edge) return 1;
    try {
        MEDDLY::dd_edge* e = static_cast<MEDDLY::dd_edge*>(edge);
        // For all quasi-reduced forest types, node handle 0 means:
        //   MT-boolean:  false terminal    (empty set)
        //   MT-integer:  integer-0 terminal (zero function, counts as empty)
        //   EV+MDD:      OMEGA_INFINITY    (all minterms absent)
        return (e->getNode() == 0) ? 1 : 0;
    } catch (...) { return 1; }
}

/* ------------------------------------------------------------------ */
} // extern "C"
/* ------------------------------------------------------------------ */
