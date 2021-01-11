module UWDDynam
using Catlab
using Catlab.WiringDiagrams
using Catlab.CategoricalAlgebra
using Catlab.CategoricalAlgebra.FinSets
using Catlab.Theories

using Catlab.WiringDiagrams.UndirectedWiringDiagrams: AbstractUWD
import Catlab.WiringDiagrams: oapply

using OrdinaryDiffEq, DynamicalSystems
import OrdinaryDiffEq: ODEProblem
import DynamicalSystems: DiscreteDynamicalSystem

export AbstractResourceSharer, ContinuousResourceSharer, DiscreteResourceSharer,
euler_approx, nstates, nports, portmap, portfunction, 
eval_dynamics, eval_dynamics!, exposed_states, fills, induced_states

using Base.Iterators
import Base: show, eltype

"""     AbstractResourceSharer{T}

An undirected open dynamical system with 

In the operad algebra, `r::AbstractResourceSharer` has type signature
`r.nports`.
"""
abstract type AbstractResourceSharer{T} end

"""An undirected open continuous system

The dynamics must be of the form du/dt = f(u,p,t)
"""
struct ContinuousResourceSharer{T} <: AbstractResourceSharer{T}
  nports::Int
  nstates::Int
  dynamics::Function
  portmap::Vector{Int64}
end

"""An undirected open discrete system

The dynamics must be of the form u1 = f(u0,p,t)
"""
struct DiscreteResourceSharer{T} <: AbstractResourceSharer{T}
    nports::Int
    nstates::Int
    dynamics::Function
    portmap::Vector{Int64}
end

ContinuousResourceSharer{T}(nstates::Int, dynamics::Function) where T = 
    ContinuousResourceSharer{T}(nstates,nstates, dynamics, Vector{Int64}(1:nstates))
DiscreteResourceSharer{T}(nstates::Int, dynamics::Function) where T = 
    DiscreteResourceSharer{T}(nstates,nstates, dynamics, Vector{Int64}(1:nstates))

nstates(r::AbstractResourceSharer) = r.nstates
nports(r::AbstractResourceSharer)  = r.nports
portmap(r::AbstractResourceSharer) = r.portmap
portfunction(r::AbstractResourceSharer) = FinFunction(r.portmap, nstates(r))
exposed_states(r::AbstractResourceSharer, u::AbstractVector) = getindex(u, portmap(r))

eval_dynamics(r::AbstractResourceSharer, u::AbstractVector, p, t::Real) = r.dynamics(u, p, t)
eval_dynamics!(du, r::AbstractResourceSharer, u::AbstractVector, p, t::Real) = begin
    du .= eval_dynamics(r, u, p, t)
end
eval_dynamics(r::AbstractResourceSharer, u::AbstractVector) = eval_dynamics(r, u, [], 0)
eval_dynamics(r::AbstractResourceSharer, u::AbstractVector, p) = eval_dynamics(r, u, p, 0)

show(io::IO, vf::ContinuousResourceSharer) = print("ContinuousResourceSharer(ℝ^$(vf.nstates) → ℝ^$(vf.nstates)) with $(vf.nports) exposed ports")
show(io::IO, vf::DiscreteResourceSharer) = print("DiscreteResourceSharer(ℝ^$(vf.nstates) → ℝ^$(vf.nstates)) with $(vf.nports) exposed ports")
eltype(r::AbstractResourceSharer{T}) where T = T

"""Transforms a continuous resource sharer into a discrete
resource sharer via Euler's method.
"""
euler_approx(f::ContinuousResourceSharer{T}, h::Float64) where T = DiscreteResourceSharer{T}(
    nports(f), nstates(f), 
    (u, p, t) -> u + h*eval_dynamics(f, u, p, t),
    f.portmap
)

euler_approx(f::ContinuousResourceSharer{T}) where T = DiscreteResourceSharer{T}(
    nports(f), nstates(f), 
    (u, p, t) -> u + p[end]*eval_dynamics(f, u, p[1:end-1], t),
    f.portmap
)

euler_approx(fs::Vector{ContinuousResourceSharer{T}}, args...) where T = 
    map(f->euler_approx(f,args...), fs)

euler_approx(fs::AbstractDict{S, ContinuousResourceSharer{T}}, args...) where {S, T} = 
    Dict(name => euler_approx(f, args...) for (name, f) in fs)

"""     ODEProblem(r::ContinuousResourceSharer, u0::Vector, tspan)

Constructs an ODEProblem from the vector field defined by `r.dynamics(u,p,t)`.
"""
ODEProblem(r::ContinuousResourceSharer, u0::AbstractVector, tspan::Tuple{Real, Real}, p=nothing) = 
    ODEProblem(r.dynamics, u0, tspan, p)

"""DiscreteDynamicalSystem(r::DiscreteResourceSharer, u0::Vector, p)

Constructs a DiscreteDynamicalSystem from the eom `r.dynamics(u,p,t)`. 

Pass `nothing` in place of `p` if your system does not have parameters.
"""
DiscreteDynamicalSystem(r::DiscreteResourceSharer{T}, u0::AbstractVector, p; t0::Int = 0) where T = begin
    if nstates(r) == 1
      DiscreteDynamicalSystem1d(r, u0[1], p; t0 = t0)
    else
      !(T <: AbstractFloat) || error("Cannot construct a DiscreteDynamicalSystem if the type is a float")
      DiscreteDynamicalSystem((u,p,t) -> SVector{nstates(r)}(eval_dynamics(r,u,p,t)), u0, p; t0=t0)
    end
  end
  
  DiscreteDynamicalSystem(r::DiscreteResourceSharer, u0::Real, p; t0::Int = 0) = 
    DiscreteDynamicalSystem1d(r, u0, p; t0 = t0) 
  
  # if the system is 1D then the state must be represented by a number NOT by a 1D array
  DiscreteDynamicalSystem1d(r::DiscreteResourceSharer{T}, u0::Real, p; t0::Int = 0) where T = begin
    nstates(r) == 1 || error("The resource sharer must have exactly 1 state")
    !(T <: AbstractFloat) || error("Cannot construct a DiscreteDynamicalSystem if the type is a float")
    DiscreteDynamicalSystem((u,p,t) -> eval_dynamics(r,[u],p,t)[1], u0, p; t0 = t0)
  end



""" Checks if a resource sharer is of the correct type signature to 
fill a box in an undirected wiring diagram.
"""
function fills(r::AbstractResourceSharer, d::AbstractUWD, b::Int)
    b <= nparts(d, :Box) || error("Trying to fill box $b, when $d has fewer than $b boxes")
    return nports(r) == length(incident(d, b, :box))
end


oapply(d::AbstractUWD, x::AbstractResourceSharer) = 
    oapply(d, collect(repeated(x, nboxes(d))))

"""     oapply(d, generators::Dict)

A version of oapply

- d: An undirected wiring diagram whose boxes represent systems
- generator: A dictionary mapping the name of each box to its corresponding
resource sharer

Each box of the undirected wiringdiagram must be filled by a resource sharer
of the appropriate type signature.
"""
oapply(d::HypergraphDiagram, xs::AbstractDict) = 
    oapply(d, [xs[name] for name in subpart(d, :name)])

"""     oapply(d, xs::Vector)

Implements the operad algebra Dynam given a composition pattern (implemented
by an undirected wiring diagram) and primitive systems (implemented by
a collection of resource sharers). Returns the composite resource sharer.

- d: An undirected wiring diagram whose boxes represent systems
- xs: A vector representing the resources sharers which fill the boxes

Each box of the undirected wiring diagram must be filled by a resource sharer of the appropriate
type signature. 
"""
oapply(d::AbstractUWD, xs::Vector{ResourceSharer}) where {ResourceSharer <: AbstractResourceSharer} =
    oapply(d, xs, induced_states(d, xs))



function oapply(d::AbstractUWD, xs::Vector{ResourceSharer}, S′::Pushout) where {ResourceSharer <: AbstractResourceSharer}
    
    S = coproduct((FinSet∘nstates).(xs))
    states(b::Int) = legs(S)[b].func

    v = induced_dynamics(d, xs, legs(S′)[1], states)

    junction_map = legs(S′)[2]
    outer_junction_map = FinFunction(subpart(d, :outer_junction), nparts(d, :Junction))

    return ResourceSharer(
        nparts(d, :OuterPort), 
        length(apex(S′)), 
        v, 
        compose(outer_junction_map, junction_map).func)
end


function induced_states(d::AbstractUWD, xs::Vector{ResourceSharer}) where {ResourceSharer <: AbstractResourceSharer}
    for box in parts(d, :Box)
        fills(xs[box], d, box) || error("$(xs[box]) does not fill box $box")
    end
    
    S = coproduct((FinSet∘nstates).(xs))  
    P = coproduct((FinSet∘nports).(xs))
    total_portfunction = copair([compose( portfunction(xs[i]), legs(S)[i]) for i in 1:length(xs)])
    
    return pushout(total_portfunction, FinFunction(subpart(d, :junction), nparts(d, :Junction)))
end


function induced_dynamics(d::AbstractUWD, xs::Vector{ContinuousResourceSharer{T}}, state_map::FinFunction, states::Function) where T
  
    function v(u′::AbstractVector, p, t::Real)
      u = getindex(u′,  state_map.func)
      du = zero(u)
      # apply dynamics
      for b in parts(d, :Box)
        eval_dynamics!(view(du, states(b)), xs[b], view(u, states(b)), p, t)
      end
      # add along junctions
      du′ = [sum(Array{T}(view(du, preimage(state_map, i)))) for i in codom(state_map)]
      return du′
    end

end

function induced_dynamics(d::AbstractUWD, xs::Vector{DiscreteResourceSharer{T}}, state_map::FinFunction, states::Function) where T
    function v(u′::AbstractVector, p, t::Real)
        u0 = getindex(u′,  state_map.func)
        u1 = zero(u0)
        # apply dynamics
        for b in parts(d, :Box)
          eval_dynamics!(view(u1, states(b)), xs[b], view(u0, states(b)), p, t)
        end
        Δu = u1 - u0
        # add along junctions
        return u′+ [sum(Array{T}(view(Δu, preimage(state_map, i)))) for i in codom(state_map)]
    end
end

end #module