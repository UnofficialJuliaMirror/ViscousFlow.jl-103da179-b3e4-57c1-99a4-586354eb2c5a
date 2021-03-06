#=
Philosophy and convention:
A node is defined as the center of a grid cell. Grid cells may be those
in a primary grid or those in a dual grid.

The definitions "dual" and "primal" are made based on their conventional use
in holding fluid dynamic data. For example, pressure is held in primal nodes,
vorticity and streamfunction at dual nodes.

The definitions here are made with a "dual grid" in mind. That is, the grid is
defined by an integer number of dual cells in each direction. If a "primal grid"
is needed, then all of the defintions can be swapped (primal -> dual, dual -> primal).

Also, note that there might be dual cells that are "ghosts" (i.e. lie outside
the grid), but these are not distinguished in these basic definitions and operators.
=#

#=
Notes on data types:
All data types can be reduced to one of two different types in each direction.
(1) Lying on dual cell centers (C), numbered 1 through N
(2) Lying on dual cell edges (E), numbered 1 through N-1 (i.e. lying midway between C)

For example, Nodes{Dual} by definition lie on dual cell centers in both directions,
so they would be C x C. Nodes{Primal} are aligned with the corners of the dual
cells, so they lie along dual cell edges in both directions, E x E.

Nodes{Dual}    -- C x C
Nodes{Primal}  -- E x E
XEdges{Dual}   -- E x C
YEdges{Dual}   -- C x E
XEdges{Primal} -- C x E
YEdges{Primal} -- E x C

This is important when considering the interpolation and differentiation operations,
both of which must account for the relative indexing between E and C. The
key to remember is that E[1] is bounded by C[1] and C[2] in our indexing convention,
so that, for either interpolation or differentiation:
      E[i] <- C[i], C[i+1] for i in 1:N-1
and
      C[i] <- E[i-1], E[i] for i in 2:N-1
and
      C[i] <- C[i] for i in 1:N
and
      E[i] <- E[i] for i in 1:N-1
=#


module Fields

import Base: @propagate_inbounds, show, summary

#using Compat
using FFTW
using SpecialFunctions
using Statistics

using LinearAlgebra
using SparseArrays

import LinearAlgebra: mul!, ldiv!, cross, ×, dot, ⋅
import Base: parentindices
const GAMMA = MathConstants.γ

export Primal, Dual, ScalarGridData, VectorGridData, GridData,
       Edges, Nodes, XEdges, YEdges,
       EdgeGradient, NodePair,
       Points, ScalarData, VectorData, TensorData,
       celltype,
       diff!,interpolate!,
       curl, curl!, Curl, divergence, divergence!, Divergence,
       grad, grad!, Grad,
       laplacian, laplacian!, laplacian_symm!, plan_laplacian, plan_laplacian!,
       helmholtz, helmholtz!, plan_helmholtz, plan_helmholtz!,
       plan_intfact,plan_intfact!,Identity,
       product, product!, ∘,
       directional_derivative!, directional_derivative_conserve!, curl_cross!,
       convective_derivative!, convective_derivative_rot!,
       coordinates,
       DDF, GradDDF,
       Regularize, RegularizationMatrix, InterpolationMatrix,
       CircularConvolution

abstract type CellType end
abstract type Primal <: CellType end
abstract type Dual <: CellType end

abstract type GridData{NX,NY,T} <: AbstractMatrix{T} end

abstract type ScalarGridData{NX,NY,T} <: GridData{NX,NY,T} end

abstract type VectorGridData{NX,NY,T} <: GridData{NX,NY,T} end


macro wraparray(wrapper, field, N)
    S = eval(wrapper)
    @assert S <: AbstractArray "Wrapped type must be a subtype of AbstractArray"
    while supertype(S) <: AbstractArray
        S = supertype(S)
    end
    #T = supertype(eval(wrapper))
    #@assert T <: AbstractArray "Wrapped type must be a subtype of AbstractArray"
    #el_type, N = S.parameters

    quote
        Base.parent(A::$wrapper) = A.$field
        Base.size(A::$wrapper) = size(A.$field)
        parentindices(A::$wrapper) = parentindices(A.$field)

        if $N > 1
          function Base.show(io::IO, m::MIME"text/plain", A::$wrapper)
            println(io, "$(typeof(A)) data")
            println(io, "Printing in grid orientation (lower left is (1,1))")
            show(io,m, reverse(transpose(A.$field),dims=1))
          end
          #function Base.summary(io::IO, A::$wrapper)
          #  println(io, "$(typeof(A)) data")
          #  print(io, "Printing in grid orientation (lower left is (1,1))")
          #end
        end

        @propagate_inbounds Base.getindex(A::$wrapper, i::Int) = A.$field[i]
        @propagate_inbounds Base.setindex!(A::$wrapper, v, i::Int) = A.$field[i] = convert(eltype(A.$field), v)
        if $N > 1
          @propagate_inbounds Base.getindex(A::$wrapper, I::Vararg{Int, $N}) = A.$field[I...]
          @propagate_inbounds Base.setindex!(A::$wrapper, v, I::Vararg{Int, $N}) = A.$field[I...] = convert(eltype(A.$field), v)
        end
    end
end

celltype(w::GridData) = typeof(w).parameters[1]

function othertype end

macro othertype(celltype, k)
    esc(quote
        Fields.othertype(::$celltype) = $k
        Fields.othertype(::Type{$celltype}) = $k
    end)
end

@othertype Primal Dual
@othertype Dual Primal
@othertype CellType CellType

# This macro allows us to access scalar grid data via just the wrapper itself
@wraparray ScalarGridData data 2

include("fields/nodes.jl")
include("fields/edges.jl")
include("fields/collections.jl")

# (ctype,dnx,dny,shiftx,shifty)
scalarlist = ((:(Nodes{Primal,NX,NY,T}), 1,1,0.0,0.0),
              (:(Nodes{Dual,NX,NY,T}),   0,0,0.5,0.5),
              (:(XEdges{Primal,NX,NY,T}),0,1,0.5,0.0),
              (:(YEdges{Primal,NX,NY,T}),1,0,0.0,0.5),
              (:(XEdges{Dual,NX,NY,T}),  1,0,0.0,0.5),
              (:(YEdges{Dual,NX,NY,T}),  0,1,0.5,0.0))

# (ctype,dunx,duny,dvnx,dvny,shiftux,shiftuy,shiftvx,shiftvy)
vectorlist = ((:(Edges{Primal,NX,NY,T}),          0,1,1,0,0.5,0.0,0.0,0.5),
              (:(Edges{Dual,NX,NY,T}),            1,0,0,1,0.0,0.5,0.5,0.0),
              (:(NodePair{Dual,Dual,NX,NY,T}),    0,0,0,0,0.5,0.5,0.5,0.5),
              (:(NodePair{Primal,Dual,NX,NY,T}),  1,1,0,0,0.0,0.0,0.5,0.5),
              (:(NodePair{Dual,Primal,NX,NY,T}),  0,0,1,1,0.5,0.5,0.0,0.0),
              (:(NodePair{Primal,Primal,NX,NY,T}),1,1,1,1,0.0,0.0,0.0,0.0))

tensorlist = ((:(EdgeGradient{Dual,Primal,NX,NY,T}), 0,0,1,1,0.5,0.5,0.0,0.0),
              (:(EdgeGradient{Primal,Dual,NX,NY,T}), 1,1,0,0,0.0,0.0,0.5,0.5))

include("fields/basicoperations.jl")
include("fields/points.jl")


CollectedData = Union{EdgeGradient{R,S,NX,NY,T},NodePair{R,S,NX,NY,T}} where {R,S,NX,NY,T}

"""
    coordinates(w::GridData;[dx=1.0],[I0=(1,1)])

Return a tuple of the ranges of the physical coordinates in each direction for grid
data `w`. If `w` is of `Nodes` type, then it returns a tuple of the form
`xg,yg`. If `w` is of `Edges` or `NodePair` type, then it returns a tuple of
the form `xgu,ygu,xgv,ygv`.

The optional keyword argument `dx` sets the grid spacing; its default is `1.0`. The
optional keyword `I0` accepts a tuple of integers to set the index pair of the
primal nodes that coincide with the origin. The default is `(1,1)`.

# Example

```jldoctest
julia> w = Nodes(Dual,(12,22));

julia> xg, yg = coordinates(w,dx=0.1)
(-0.05:0.1:1.05, -0.05:0.1:2.0500000000000003)
```
"""
function coordinates end

for (ctype,dnx,dny,shiftx,shifty) in scalarlist
   @eval coordinates(w::$ctype;dx::Float64=1.0,I0::Tuple{Int,Int}=(1,1)) where {NX,NY,T} =
    dx.*((1-I0[1]-$shiftx):(NX-$dnx-I0[1]-$shiftx),
         (1-I0[2]-$shifty):(NY-$dny-I0[2]-$shifty))

end

for (ctype,dunx,duny,dvnx,dvny,shiftux,shiftuy,shiftvx,shiftvy) in vectorlist
   @eval coordinates(w::$ctype;dx::Float64=1.0,I0::Tuple{Int,Int}=(1,1)) where {NX,NY,T} =
    dx.*((1-I0[1]-$shiftux):(NX-$dunx-I0[1]-$shiftux),
         (1-I0[2]-$shiftuy):(NY-$duny-I0[2]-$shiftuy),
         (1-I0[1]-$shiftvx):(NX-$dvnx-I0[1]-$shiftvx),
         (1-I0[2]-$shiftvy):(NY-$dvny-I0[2]-$shiftvy))


end

include("fields/physicalgrid.jl")
include("fields/operators.jl")

end
