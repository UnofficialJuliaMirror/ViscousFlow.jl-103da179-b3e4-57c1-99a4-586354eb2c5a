using RecipesBase
using ColorTypes
import PlotUtils: cgrad

const mygreen = RGBA{Float64}(151/255,180/255,118/255,1)
const mygreen2 = RGBA{Float64}(113/255,161/255,103/255,1)
const myblue = RGBA{Float64}(74/255,144/255,226/255,1)

@recipe function plot(w::Fields.Nodes{T,NX,NY}) where {T,NX,NY}
  grid --> :none
  ratio := 1
  linewidth --> 1
  legend --> :none
  framestyle --> :frame
  levels --> linspace(minimum(w.data),maximum(w.data),16)
  @series begin
    seriestype --> :contour
    transpose(w.data)
  end
end

@recipe function plot(x::AbstractArray{S,1},y::AbstractArray{S,1},w::Fields.Nodes{T,NX,NY}) where {S,T,NX,NY}
      grid --> :none
      ratio := 1
      linewidth --> 1
      legend --> :none
      framestyle --> :frame
      levels --> linspace(minimum(w.data),maximum(w.data),16)
      @series begin
        seriestype --> :contour
        x,y,transpose(w.data)
      end
end

@recipe function plot(q::T) where {T <: Union{Fields.Edges,Fields.NodePair}}
    #wx = Fields.Nodes(Dual,(NX,NY))
    #wy = Fields.Nodes(Dual,(NX,NY))
    #shift!((wx,wy),q)
    layout := (1,2)
    seriestype --> :contour
    grid --> :none
    ratio := 1
    linewidth --> 1
    legend --> :none
    framestyle --> :frame
    @series begin
      subplot := 1
      #levels --> linspace(minimum(wx.data),maximum(wx.data),16)
      levels --> linspace(minimum(q.u),maximum(q.u),16)
      #transpose(wx.data)
      transpose(q.u)
    end

    @series begin
      subplot := 2
      #levels --> linspace(minimum(wy.data),maximum(wy.data),16)
      levels --> linspace(minimum(q.v),maximum(q.v),16)
      #transpose(wy.data)
      transpose(q.v)
    end
end

@recipe function plot(b::Body)
    x = [b.x; b.x[1]]
    y = [b.y; b.y[1]]
    linecolor --> mygreen
    fillrange --> 0
    fillcolor --> mygreen
    ratio := 1
    legend := :none
    grid := false
    x := x
    y := y
    ()
end
