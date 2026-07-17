# Tests for MDD traversal: node handles, structure inspection, and
# user-defined algorithms built on the traversal primitives.

# ---------------------------------------------------------------------------
# Helper: follow root-to-terminal path for given variable values.
# var_values[level] = 0-indexed value for the variable at that level.
# Handles fully-reduced MDDs (skipped levels are transparent).
# ---------------------------------------------------------------------------
function _evaluate(f, node, var_values)
    while !is_terminal(node)
        lv   = node_level(f, node)
        node = node_children(f, node)[var_values[lv] + 1]   # 0→1-indexed
    end
    terminal_value(f, node)
end

# ---------------------------------------------------------------------------
# Helper: collect all distinct reachable nodes via BFS.
# ---------------------------------------------------------------------------
function _all_nodes(f, root)
    seen  = Set{NodeHandle}()
    queue = [root]
    while !isempty(queue)
        n = pop!(queue)
        n ∈ seen && continue
        push!(seen, n)
        is_terminal(n) && continue
        for c in node_children(f, n)
            push!(queue, c)
        end
    end
    seen
end

# ---------------------------------------------------------------------------

@testset "num_vars / level_size" begin
    dom = Domain([3, 4, 2])   # 3 variables with sizes 3, 4, 2
    f   = MDDForestBool(dom)

    @test num_vars(f) == 3
    @test level_size(f, 1) == 3
    @test level_size(f, 2) == 4
    @test level_size(f, 3) == 2
end

@testset "root_node / is_terminal — boolean" begin
    dom = Domain([4, 4])
    f   = MDDForestBool(dom)

    # Empty edge → false terminal (handle 0)
    e_empty = Edge(f)
    r = root_node(e_empty)
    @test is_terminal(r)
    @test r == NodeHandle(0)
    @test node_level(f, r) == 0
    @test terminal_value(f, r) == false

    # Single-minterm edge → internal root
    e = Edge(f, [1, 2])
    r = root_node(e)
    @test !is_terminal(r)
    @test node_level(f, r) >= 1
    @test length(node_children(f, r)) == level_size(f, node_level(f, r))
end

@testset "terminal_value — boolean" begin
    dom = Domain([2, 2])
    f   = MDDForestBool(dom)

    # true terminal: union of all minterms in a boolean domain
    e_all = Edge(f, [0,0]) | Edge(f, [0,1]) | Edge(f, [1,0]) | Edge(f, [1,1])
    # Root should be the "true" terminal (-1) once fully reduced
    # (or an internal node if not; check terminal_value via path)
    e_pt = Edge(f, [0, 1])   # single true point
    @test _evaluate(f, root_node(e_pt), [0, 1]) == true
    @test _evaluate(f, root_node(e_pt), [0, 0]) == false
    @test _evaluate(f, root_node(e_pt), [1, 0]) == false
    @test _evaluate(f, root_node(e_pt), [1, 1]) == false
end

@testset "evaluate — boolean MDD" begin
    dom = Domain([4, 4])
    f   = MDDForestBool(dom)

    e = Edge(f, [1, 2])   # true at (1,2), false elsewhere

    @test _evaluate(f, root_node(e), [1, 2]) == true
    @test _evaluate(f, root_node(e), [0, 0]) == false
    @test _evaluate(f, root_node(e), [1, 0]) == false
    @test _evaluate(f, root_node(e), [0, 2]) == false
    @test _evaluate(f, root_node(e), [3, 3]) == false

    # Union of two minterms
    e2 = Edge(f, [2, 3])
    u  = e | e2
    @test _evaluate(f, root_node(u), [1, 2]) == true
    @test _evaluate(f, root_node(u), [2, 3]) == true
    @test _evaluate(f, root_node(u), [0, 0]) == false
end

@testset "evaluate — integer MDD" begin
    dom   = Domain([4, 4])
    int_f = MDDForestInt(dom)

    # Constant edges
    c5 = Edge(int_f, 5)
    r5 = root_node(c5)
    @test is_terminal(r5)
    @test terminal_value(int_f, r5) == 5

    c0 = Edge(int_f, 0)
    r0 = root_node(c0)
    @test is_terminal(r0)
    @test terminal_value(int_f, r0) == 0

    # Single-minterm edges
    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [3, 3], 9)

    @test _evaluate(int_f, root_node(ea), [1, 2]) == 5
    @test _evaluate(int_f, root_node(ea), [0, 0]) == 0
    @test _evaluate(int_f, root_node(eb), [3, 3]) == 9

    # Pointwise sum
    eu = ea + eb
    @test _evaluate(int_f, root_node(eu), [1, 2]) == 5
    @test _evaluate(int_f, root_node(eu), [3, 3]) == 9
    @test _evaluate(int_f, root_node(eu), [2, 2]) == 0
end

@testset "node_children length invariant" begin
    dom = Domain([3, 4, 2])
    f   = MDDForestBool(dom)

    e = Edge(f, [0, 1, 0]) | Edge(f, [1, 2, 1]) | Edge(f, [2, 0, 0])

    # Every internal node's child array must have exactly level_size(f, level) entries
    for n in _all_nodes(f, root_node(e))
        is_terminal(n) && continue
        lv = node_level(f, n)
        @test length(node_children(f, n)) == level_size(f, lv)
    end
end

@testset "cardinality via traversal" begin
    # Implement cardinality by counting 'true' terminals reachable from root,
    # accounting for level skipping (each skipped level multiplies by its size).
    #
    # In a fully-reduced MDD, child(node, lv) may be at level lv' < lv - 1.
    # The "gap" levels contribute a multiplicative factor of their sizes.
    dom = Domain([4, 4])
    f   = MDDForestBool(dom)

    function my_card(f, node, cache = Dict{NodeHandle, Float64}())
        haskey(cache, node) && return cache[node]
        result = if is_terminal(node)
            terminal_value(f, node) ? 1.0 : 0.0
        else
            lv = node_level(f, node)
            children = node_children(f, node)
            total = 0.0
            for c in children
                # Account for any skipped levels between lv-1 and child's level
                child_lv   = is_terminal(c) ? 0 : node_level(f, c)
                gap_factor = prod(Float64(level_size(f, k))
                                  for k in (child_lv + 1):(lv - 1);
                                  init = 1.0)
                total += gap_factor * my_card(f, c, cache)
            end
            total
        end
        cache[node] = result
        result
    end

    for (vars, expected_card) in [
        ([Edge(f, [0,0])],                                    1.0),
        ([Edge(f, [0,0]), Edge(f, [1,1])],                   2.0),
        ([Edge(f, [0,0]), Edge(f, [1,1]), Edge(f, [2,2])],   3.0),
    ]
        e = reduce(|, vars)
        @test my_card(f, root_node(e)) ≈ cardinality(e)
    end
end

@testset "NodeHandle type" begin
    @test NodeHandle === Int32
    @test is_terminal(NodeHandle(0))
    @test is_terminal(NodeHandle(-1))
    @test !is_terminal(NodeHandle(1))
    @test !is_terminal(NodeHandle(42))
end

# ---------------------------------------------------------------------------
# create_node — the construction counterpart of node_children.
# ---------------------------------------------------------------------------

@testset "create_node round-trip" begin
    dom = Domain([3, 3, 3])
    f   = MDDForestBool(dom)
    e   = Edge(f, [0, 1, 2]) | Edge(f, [1, 1, 2]) | Edge(f, [2, 0, 1])
    r   = root_node(e)

    rebuilt = create_node(f, node_level(f, r), node_children(f, r))

    # Nodes are hash-consed, so rebuilding an identical node must return the
    # very same handle — this also proves the child references are correct.
    @test root_node(rebuilt) == r
    @test cardinality(rebuilt) == cardinality(e)
end

@testset "create_node applies reduction rules" begin
    dom = Domain([3, 3, 3])
    f   = MDDForestBool(dom)
    sub = root_node(Edge(f, [0, 0, 0]) | Edge(f, [0, 0, 1]) | Edge(f, [0, 0, 2]))

    # All children equal ⇒ redundant node ⇒ the child itself comes back.
    @test root_node(create_node(f, 3, NodeHandle[sub, sub, sub])) == sub
end

@testset "create_node borrows child handles" begin
    dom = Domain([3, 3, 3])
    f   = MDDForestBool(dom)
    e   = Edge(f, [0, 1, 2]) | Edge(f, [1, 1, 2]) | Edge(f, [2, 0, 1])
    r   = root_node(e)
    ch  = node_children(f, r)

    # Dropping a node built from `ch` must not disturb the edge they came from.
    built = create_node(f, node_level(f, r), ch)
    finalize(built)
    GC.gc()

    @test cardinality(e) == 3.0
    @test node_children(f, r) == ch
end

@testset "edge_from_node" begin
    dom = Domain([3, 3, 3])
    f   = MDDForestBool(dom)
    e   = Edge(f, [0, 1, 2]) | Edge(f, [1, 1, 2]) | Edge(f, [2, 0, 1])
    r   = root_node(e)

    # Inverse of root_node.
    @test root_node(edge_from_node(f, r)) == r
    @test cardinality(edge_from_node(f, r)) == cardinality(e)

    # Terminals: false ⇒ empty, true ⇒ the whole space.
    @test cardinality(edge_from_node(f, NodeHandle(0))) == 0.0
    @test cardinality(edge_from_node(f, NodeHandle(-1))) == 27.0

    # A wrapped subgraph can be used with the edge-level operations.
    ch  = node_children(f, r)
    sub = edge_from_node(f, ch[2])
    @test cardinality(sub) > 0

    # Dropping the wrapper must not disturb the edge it was reached through.
    finalize(sub)
    GC.gc()
    @test cardinality(e) == 3.0
    @test node_children(f, r) == ch
end

@testset "forest statistics" begin
    dom = Domain([3, 3, 3])
    f   = MDDForestBool(dom)

    @test current_num_nodes(f) == 0
    @test peak_num_nodes(f) == 0

    e = Edge(f, [0, 1, 2]) | Edge(f, [1, 1, 2]) | Edge(f, [2, 0, 1])
    n1 = current_num_nodes(f)
    @test n1 > 0
    @test peak_num_nodes(f) >= n1

    # Reset drops the peak to the current count, so a later computation is
    # measured on its own.
    reset_peak_num_nodes!(f)
    @test peak_num_nodes(f) == current_num_nodes(f)

    before = current_num_nodes(f)
    e2 = Edge(f, [0, 0, 0]) | Edge(f, [1, 1, 1]) | Edge(f, [2, 2, 2])
    @test current_num_nodes(f) > before
    @test peak_num_nodes(f) >= current_num_nodes(f)

    # The forest holds more than any single result: the peak is a property of
    # the computation, an edge's own node count a property of its function.
    internal_of_e2 = count(n -> !is_terminal(n), _all_nodes(f, root_node(e2)))
    @test peak_num_nodes(f) >= internal_of_e2
end

@testset "create_node argument checks" begin
    dom = Domain([3, 3, 3])
    f   = MDDForestBool(dom)
    e   = Edge(f, [0, 1, 2]) | Edge(f, [1, 1, 2])
    r   = root_node(e)
    lv  = node_level(f, r)
    ch  = node_children(f, r)

    @test_throws ErrorException create_node(f, lv, ch[1:end-1])   # count ≠ level size
    @test_throws ErrorException create_node(f, 0, ch)             # level too low
    @test_throws ErrorException create_node(f, num_vars(f) + 1, ch)
end
