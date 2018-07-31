# RK

"""
    RK(u,Δt,r₁;[rk::RKParams=RK31])

Construct an integrator to advance a system of the form

du/dt = r₁(u,t)

The resulting integrator will advance the state `u` by one time step, `Δt`.

# Arguments

- `u` : example of state vector data
- `Δt` : time-step size
- `r₁` : operator acting on type `u` and `t` and returning `u`
"""
struct RK{NS,FR1,TU}

  # time step size
  Δt :: Float64

  rk :: RKParams

  r₁ :: FR1  # function of u and t, returns TU

  # scratch space
  qᵢ :: TU
  w :: Vector{TU}

end


function (::Type{RK})(u::TU,Δt::Float64,rhs::FR1;
                          rk::RKParams{NS}=RK31) where {TU,FR1,NS}

    # check for methods for r₁ and r₂
    if method_exists(rhs,(TU,Float64))
        r₁ = rhs
    else
        error("No valid operator for r₁ supplied")
    end

    # scratch space
    qᵢ = deepcopy(u)
    w = [deepcopy(u) for i = 1:NS-1]

    # fuse the time step size into the coefficients for some cost savings
    rkdt = deepcopy(rk)
    rkdt.a .*= Δt
    rkdt.c .*= Δt

    rksys = RK{NS,typeof(r₁),TU}(Δt,rkdt,r₁,qᵢ,w)

    #pre-compile
    rksys(0.0,u)

    return rksys
end

function Base.show(io::IO, scheme::RK{NS,FR1,TU}) where {NS,FR1,TU}
    println(io, "Order-$NS RK integator with")
    println(io, "   State of type $TU")
    println(io, "   Time step size $(scheme.Δt)")
end

# Advance the RK solution by one time step
function (scheme::RK{NS,FR1,TU})(t::Float64,u::TU) where {NS,FR1,TU}
  @get scheme (Δt,rk,r₁,qᵢ,w)

  i = 1
  qᵢ .= u

  if NS > 1
    # first stage, i = 1
    tᵢ₊₁ = t + rk.c[i]

    w[i] .= rk.a[i,i].*r₁(u,tᵢ₊₁) # gᵢ

    u .= qᵢ .+ w[i]

    # stages 2 through NS-1
    for i = 2:NS-1
      tᵢ₊₁ = t + rk.c[i]
      w[i-1] ./= rk.a[i-1,i-1] # w(i,i-1)
      w[i] .= rk.a[i,i].*r₁(u,tᵢ₊₁) # gᵢ

      u .= qᵢ .+ w[i] # r₁
      for j = 1:i-1
        u .+= rk.a[i,j]*w[j]
      end

    end
    i = NS
    w[i-1] ./= rk.a[i-1,i-1] # w(i,i-1)
  end

  # final stage (assembly)
  t = t + rk.c[i]
  u .= qᵢ .+ rk.a[i,i].*r₁(u,t) # r₁
  for j = 1:i-1
    u .+= rk.a[i,j]*w[j] # r₁
  end

  return t, u

end
