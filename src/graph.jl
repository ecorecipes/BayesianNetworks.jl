"""
Derived graph views. The DAG of a Bayesian network is not stored; it is read off the
mechanisms and their inputs. Graphs are Graphs.jl's `SimpleDiGraph` and `SimpleGraph`,
the lightweight and idiomatic representation of a plain graph, and the vertex ids
coincide with variable part ids: vertex `i` is variable `i`.
"""

"""
    variable_graph(bn) -> Graphs.SimpleDiGraph{Int}

The directed graph with one vertex per variable (vertex `i` is variable `i`) and one
edge per `Input`, from the input variable to the target of the input's mechanism.
Parallel inputs from the same variable to the same mechanism collapse to one edge, as
`SimpleDiGraph` holds no multiple edges.
"""
function variable_graph(bn::AbstractBayesNet)
    g = SimpleDiGraph{Int}(nparts(bn, :Variable))
    for i in parts(bn, :Input)
        add_edge!(g, subpart(bn, i, :input_variable),
                  subpart(bn, subpart(bn, i, :input_mechanism), :target))
    end
    return g
end

# Kahn's algorithm with the smallest available variable id taken first, so the order is
# deterministic. Returns the order found and the ids that could not be placed.
function _kahn(bn::AbstractBayesNet)
    n = nparts(bn, :Variable)
    indegree = zeros(Int, n)
    succ = [Int[] for _ in 1:n]
    for i in parts(bn, :Input)
        s = subpart(bn, i, :input_variable)
        t = subpart(bn, subpart(bn, i, :input_mechanism), :target)
        push!(succ[s], t)
        indegree[t] += 1
    end
    ready = sort!(findall(==(0), indegree); rev=true)
    order = Int[]
    while !isempty(ready)
        v = pop!(ready)
        push!(order, v)
        for t in succ[v]
            indegree[t] -= 1
            if indegree[t] == 0
                push!(ready, t)
                sort!(ready; rev=true)
            end
        end
    end
    remaining = findall(>(0), indegree)
    return order, remaining
end

"""
    is_acyclic(bn) -> Bool

Whether the derived variable graph has no directed cycle.
"""
is_acyclic(bn::AbstractBayesNet) = isempty(last(_kahn(bn)))

"""
    topological_order(bn) -> Vector{Int}

Variable part ids in an order where every parent precedes its children (ties broken by
the smallest id). Throws [`CyclicBayesNetError`](@ref) if the graph has a cycle.
"""
function topological_order(bn::AbstractBayesNet)
    order, remaining = _kahn(bn)
    isempty(remaining) ||
        throw(CyclicBayesNetError(variable_name.(Ref(bn), remaining), remaining))
    return order
end

"""
    moral_graph(bn) -> Graphs.SimpleGraph{Int}

The moral graph: an undirected graph on the variables in which each variable is joined
to every parent and the parents of each mechanism are joined pairwise ("married").
Each undirected edge is stored once. Moralisation is the
first step from a directed network to the undirected representation used by junction
trees [KollerFriedman2009](@cite); [LorenzinZanasi2025](@cite) give the categorical
account.
"""
function moral_graph(bn::AbstractBayesNet)
    g = SimpleGraph{Int}(nparts(bn, :Variable))
    seen = Set{Tuple{Int,Int}}()
    link! = (a, b) -> begin
        a == b && return
        key = minmax(a, b)
        key in seen && return
        push!(seen, key)
        add_edge!(g, key...)
    end
    for m in parts(bn, :Mechanism)
        t = subpart(bn, m, :target)
        ps = inputs(bn, m)
        for (i, p) in enumerate(ps)
            link!(p, t)
            for q in ps[(i + 1):end]
                link!(p, q)
            end
        end
    end
    return g
end
