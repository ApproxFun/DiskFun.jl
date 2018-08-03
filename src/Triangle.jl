export Triangle, KoornwinderTriangle, ProductTriangle, TriangleWeight, WeightedTriangle


## Triangle Def
# currently right trianglel
struct Triangle <: BivariateDomain{Float64}
    a::Vec{2,Float64}
    b::Vec{2,Float64}
    c::Vec{2,Float64}
end

Triangle() = Triangle(Vec(0,0), Vec(1,0), Vec(0,1))
canonicaldomain(::Triangle) = Triangle()

for op in (:-, :+)
    @eval begin
        $op(d::Triangle, x::Vec{2}) = Triangle($op(d.a,x), $op(d.b,x), $op(d.c,x))
        $op(x::Vec{2}, d::Triangle) = Triangle($op(x,d.a), $op(x,d.b), $op(x,d.c))
    end
end

for op in (:*, :/)
    @eval $op(d::Triangle, x::Number) = Triangle($op(d.a,x), $op(d.b,x), $op(d.c,x))
end



function tocanonical(d::Triangle, xy::Vec)
    if d.a == Vec(0,0)
        [d.b d.c] \ xy
    else
        tocanonical(d-d.a, xy-d.a)
    end
end


function fromcanonical(d::Triangle, xy::Vec)
    if d.a == Vec(0,0)
        [d.b d.c]*xy
    else
        fromcanonical(d-d.a, xy) + d.a
    end
end

function tocanonicalD(d::Triangle)
    if d.a == Vec(0,0)
        inv([d.b d.c])
    else
        tocanonicalD(d-d.a)
    end
end

#canonical is rectangle [0,1]^2
# with the map (x,y)=(s,(1-s)*t)
iduffy(st::Vec) = Vec(st[1],(1-st[1])*st[2])
iduffy(s,t) = Vec(s,(1-s)*t)
duffy(xy::Vec) = Vec(xy[1],xy[1]==1 ? zero(eltype(xy)) : xy[2]/(1-xy[1]))
duffy(x::T,y::T) where T = Vec(x,x == 1 ? zero(Y) : y/(1-x))
checkpoints(d::Triangle) = [fromcanonical(d,iduffy(Vec(.1,.2243))),
                            fromcanonical(d,iduffy(Vec(0.212423,0.3)))]

∂(d::Triangle) = PiecewiseSegment([d.a,d.b,d.c,d.a])


Base.isnan(::Triangle) = false

# expansion in OPs orthogonal to
# x^α*y^β*(1-x-y)^γ
# defined as
# P_{n-k}^{2k+β+γ+1,α}(2x-1)*(1-x)^k*P_k^{γ,β}(2y/(1-x)-1)


immutable ProductTriangle <: AbstractProductSpace{Tuple{WeightedJacobi{Segment{Float64},Float64},
                                                        Jacobi{Segment{Float64},Float64}},
                                                  Triangle,Float64}
    α::Float64
    β::Float64
    γ::Float64
    domain::Triangle
end


immutable KoornwinderTriangle <: Space{Triangle,Float64}
    α::Float64
    β::Float64
    γ::Float64
    domain::Triangle
end

KoornwinderTriangle() = KoornwinderTriangle(0,0,0)

points(K::KoornwinderTriangle, n::Integer) =
    fromcanonical.(Ref(K), points(DuffyTriangle(), n))

points(K::Triangle,n::Integer) = points(KoornwinderTriangle(0,0,0,K),n)

const TriangleSpace = Union{ProductTriangle,KoornwinderTriangle}

ProductTriangle(K::KoornwinderTriangle) = ProductTriangle(K.α,K.β,K.γ,K.domain)

canonicaldomain(sp::ProductTriangle) = Segment(0,1)^2
tocanonical(sp::ProductTriangle, x...) = duffy(tocanonical(domain(sp),x...))
fromcanonical(sp::ProductTriangle, x...) = fromcanonical(domain(sp),iduffy(x...))
setdomain(K::KoornwinderTriangle, d::Triangle) = KoornwinderTriangle(K.α,K.β,K.γ,d)


for TYP in (:ProductTriangle,:KoornwinderTriangle)
    @eval begin
        $TYP(α,β,γ) = $TYP(α,β,γ,Triangle())
        $TYP(T::Triangle) = $TYP(0.,0.,0.,T)
        spacescompatible(K1::$TYP,K2::$TYP) =
            K1.α==K2.α && K1.β==K2.β && K1.γ==K2.γ
    end
end



Space(T::Triangle) = KoornwinderTriangle(T)

# Use DuffyMap with

struct DuffyTriangle{S,T} <: Space{Triangle,T}
    space::S
    domain::Triangle
    function DuffyTriangle{S,T}(s::S, d::Triangle) where {S,T}
        @assert domain(s) == Interval(0,1)^2
        new{S,T}(s, d)
    end
end

DuffyTriangle(s::S, d) where S = DuffyTriangle{S,ApproxFun.rangetype(S)}(s, d)
DuffyTriangle() = DuffyTriangle(Chebyshev(0..1)^2, Triangle())
DuffyTriangle(d::Triangle) = DuffyTriangle(Chebyshev()^2, d)

function points(S::DuffyTriangle, N)
    pts = points(S.space, N)
    fromcanonical.(S.domain, iduffy.(pts))
end

plan_transform(S::DuffyTriangle, n::Integer) = TransformPlan(S, plan_transform(S.space,n), Val{false})
plan_transform(S::DuffyTriangle, n::AbstractVector) = TransformPlan(S, plan_transform(S.space,n), Val{false})

*(P::TransformPlan{<:Any,<:DuffyTriangle}, v::AbstractArray) = P.plan*v

evaluate(cfs::AbstractVector, S::DuffyTriangle, x) = evaluate(cfs, S.space, duffy(tocanonical(S.domain,x)))

jacobinorm(n,a,b) = if n ≠ 0
        sqrt((2n+a+b+1))*exp((lgamma(n+a+b+1)+lgamma(n+1)-log(2)*(a+b+1)-lgamma(n+a+1)-lgamma(n+b+1))/2)
    else
        sqrt(exp(lgamma(a+b+2)-log(2)*(a+b+1)-lgamma(a+1)-lgamma(b+1)))
    end

function tridenormalize!(F̌)
    for n = 0:size(F̌,1)-1, k = 0:n
        F̌[n-k+1,k+1] *= 2^k*jacobinorm(n-k,2k,0)jacobinorm(k,-0.5,-0.5)
    end
    F̌
end

function trivec(F̌)
    N = size(F̌,1)
    v = Array{eltype(F̌)}(N*(N+1) ÷2)
    j = 1
    for n=0:N-1, k=0:n
        v[j] = F̌[n-k+1,k+1]
        j += 1
    end
    v
end

function tridevec_trans(v::AbstractVector{T}) where T
    N = floor(Integer,sqrt(2length(v)) + 1/2)
    ret = zeros(T, N, N)
    j = 1
    for n=1:N,k=1:n
        ret[k,n-k+1] = v[j]
        j += 1
    end
    ret
end

struct FastKoornwinderTriangleTransformPlan{DUF,CHEB}
    duffyplan::DUF
    tri2cheb::CHEB
end

FastKoornwinderTriangleTransformPlan(v::AbstractVector, V::AbstractMatrix) =
    FastKoornwinderTriangleTransformPlan(plan_transform(DuffyTriangle(), v),
                                     plan_tri2cheb(V,0.0,-0.5,-0.5))

function FastKoornwinderTriangleTransformPlan(v::AbstractVector{T}) where T
    n = floor(Integer,sqrt(2length(v)) + 1/2)
    FastKoornwinderTriangleTransformPlan(v, Array{T}(undef,n,n))
end

function *(P::FastKoornwinderTriangleTransformPlan, v)
    v̂ = P.duffyplan*v
    F = tridevec_trans(v̂)
    F̌ = P.tri2cheb \ F
    trivec(tridenormalize!(F̌))
end

struct ShiftKoornwinderTriangleTransformPlan{FAST,CC}
    fastplan::FAST
    conversion::CC
end


function ShiftKoornwinderTriangleTransformPlan(S::KoornwinderTriangle, v::AbstractVector)
    n = floor(Integer,sqrt(2length(v)) + 1/2)
    C = Conversion(KoornwinderTriangle(0.0,-0.5,-0.5,domain(S)),S)
    ShiftKoornwinderTriangleTransformPlan(FastKoornwinderTriangleTransformPlan(v),
                                            C[Block.(1:n),Block.(1:n)])
end


*(P::ShiftKoornwinderTriangleTransformPlan, v) = P.conversion*(P.fastplan*v)

function plan_transform(K::KoornwinderTriangle, v)
    if K.α == 0 && K.β == K.γ == -0.5
        FastKoornwinderTriangleTransformPlan(v)
    elseif isapproxinteger(K.α) && isapproxinteger(K.β+0.5) &&  isapproxinteger(K.γ+0.5)
        ShiftKoornwinderTriangleTransformPlan(K, v)
    else
        KoornwinderTriangleTransformPlan(v)
    end
end



# TODO: @tensorspace
tensorizer(K::TriangleSpace) = Tensorizer((ApproxFun.repeated(true),ApproxFun.repeated(true)))

# we have each polynomial
blocklengths(K::TriangleSpace) = 1:∞

for OP in (:block,:blockstart,:blockstop)
    @eval begin
        $OP(s::TriangleSpace,M::Block) = $OP(tensorizer(s),M)
        $OP(s::TriangleSpace,M) = $OP(tensorizer(s),M)
    end
end


# support for ProductFun constructor

function factor(T::ProductTriangle,k::Integer)
    @assert k==2
    Jacobi(T.β,T.γ,Segment(0.,1.))
end

columnspace(T::ProductTriangle,k::Integer) =
    JacobiWeight(0.,k-1.,Jacobi(T.α,2k-1+T.β+T.γ,Segment(0.,1.)))

Base.sum{KT<:KoornwinderTriangle}(f::Fun{KT}) =
    Fun(f,KoornwinderTriangle(0,0,0)).coefficients[1]/2

# convert coefficients

# Fun(f::Function, S::KoornwinderTriangle) = Fun(Fun(ProductFun(f,ProductTriangle(S))),S)
# Fun(f::Fun, S::KoornwinderTriangle) = Fun(S,coefficients(f,S))


struct KoornwinderTriangleITransformPlan{PE,PT}
    plan::PE
    points::PT
end

*(P::KoornwinderTriangleITransformPlan,cfs::Vector) = P.plan.(P.points)

plan_itransform(S::KoornwinderTriangle,cfs) =
    KoornwinderTriangleITransformPlan(plan_evaluate(Fun(S,cfs)),points(S,length(cfs)))

function coefficients(f::AbstractVector,K::KoornwinderTriangle,P::ProductTriangle)
    C=totensor(K,f)
    D=Float64[2.0^(-k) for k=0:size(C,1)-1]
    fromtensor(K,(C.')*diagm(D))
end

function coefficients(f::AbstractVector,K::ProductTriangle,P::KoornwinderTriangle)
    C=totensor(K,f)
    D=Float64[2.0^(k) for k=0:size(C,1)-1]
    fromtensor(P,(C*diagm(D)).')
end


function clenshaw2D{T}(Jx,Jy,cfs::Vector{Vector{T}},x,y)
    N=length(cfs)
    bk1=zeros(T,N+1)
    bk2=zeros(T,N+2)

    Abk1x=zeros(T,N+1)
    Abk1y=zeros(T,N+1)
    Abk2x=zeros(T,N+1)
    Abk2y=zeros(T,N+1)


    @inbounds for K_int = N:-1:2
        K = Block(K_int)
        Bx,By=view(Jx,K,K),view(Jy,K,K)
        Cx,Cy=view(Jx,K,K+1),view(Jy,K,K+1)
        JxK=view(Jx,K+1,K)
        JyK=view(Jy,K+1,K)
        @inbounds for k=1:Int(K)
            bk1[k] /= inbands_getindex(JxK,k,k)
        end

        bk1[Int(K)-1] -= JyK[Int(K)-1,end]/(JxK[Int(K)-1,Int(K)-1]*JyK[end,end])*bk1[Int(K)+1]
        bk1[Int(K)]   -= JyK[Int(K),end]/(JxK[Int(K),Int(K)]*JyK[end,end])*bk1[Int(K)+1]
        bk1[Int(K)+1] /= JyK[Int(K)+1,end]

        resize!(Abk2x,Int(K))
        BLAS.blascopy!(Int(K),bk1,1,Abk2x,1)
        resize!(Abk2y,Int(K))
        Abk2y[1:Int(K)-1]=0
        Abk2y[end]=bk1[Int(K)+1]

        Abk1x,Abk2x=Abk2x,Abk1x
        Abk1y,Abk2y=Abk2y,Abk1y

        bk2 = bk1  ::Vector{T}

        bk1 = (x*Abk1x) ::Vector{T}
        Base.axpy!(y,Abk1y,bk1)
        mul!(bk1,Bx,Abk1x,-one(T),one(T))
        mul!(bk1,By,Abk1y,-one(T),one(T))
        mul!(bk1,Cx,Abk2x,-one(T),one(T))
        mul!(bk1,Cy,Abk2y,-one(T),one(T))
        Base.axpy!(one(T),cfs[Int(K)],bk1)
    end

    K = Block(1)
    Bx,By=view(Jx,K,K),view(Jy,K,K)
    Cx,Cy=view(Jx,K,K+1),view(Jy,K,K+1)
    JxK=view(Jx,K+1,K)
    JyK=view(Jy,K+1,K)

    bk1[1] /= JxK[1,1]
    bk1[1] -= JyK[1,end]/(JxK[1,1]*JyK[2,end])*bk1[2]
    bk1[2] /= JyK[2,end]

    Abk1x,Abk2x=bk1[1:1],Abk1x
    Abk1y,Abk2y=[bk1[2]],Abk1y
    (cfs[1] + x*Abk1x + y*Abk1y - Bx*Abk1x - By*Abk1y - Cx*Abk2x - Cy*Abk2y)[1]::T
end

# convert to vector of coefficients
# TODO: replace with RaggedMatrix
function totree(S,f::Fun)
    N=block(S,ncoefficients(f))
    ret = Array{Vector{eltype(f)}}(Int(N))
    for K=Block(1):N
        ret[Int(K)]=coefficient(f,K)
    end

    ret
end

struct TriangleEvaluatePlan{S,RX,RY,T}
    space::S
    coefficients::Vector{Vector{T}}
    Jx::RX
    Jy::RY
end

function canonicaljacobioperators(S::KoornwinderTriangle)
    S₁ = KoornwinderTriangle(S.α+1,S.β,S.γ,domain(S))
    J₁ = Lowering{1}(S₁)*Conversion(S,S₁)
    S₂ = KoornwinderTriangle(S.α,S.β+1,S.γ,domain(S))
    J₂ = Lowering{2}(S₂)*Conversion(S,S₂)
    J₁, J₂
end

jacobioperators(S::KoornwinderTriangle) = fromcanonical(S, canonicaljacobioperators(S)...)


function plan_evaluate(f::Fun{KoornwinderTriangle},x...)
    N = nblocks(f)
    S = space(f)
    # we cannot use true Jacobi operators because that changes the band
    # structure used in clenshaw2D to determine pseudoinverses
    Jˣ,Jʸ = canonicaljacobioperators(S)
    TriangleEvaluatePlan(S,
                totree(S,f),
                Jˣ[Block(1):Block(N+2),Block(1):Block(N+1)],
                Jʸ[Block(1):Block(N+2),Block(1):Block(N+1)])
end

(P::TriangleEvaluatePlan)(x,y) = clenshaw2D(P.Jx,P.Jy,P.coefficients,tocanonical(P.space,x,y)...)

(P::TriangleEvaluatePlan)(pt::Vec) = P(pt...)

# evaluate(f::AbstractVector,K::KoornwinderTriangle,x...) =
#     evaluate(coefficients(f,K,ProductTriangle(K)),ProductTriangle(K),x...)

evaluate(f::AbstractVector,K::KoornwinderTriangle,x...) = plan_evaluate(Fun(K,f))(x...)

# Operators



function Derivative(K::KoornwinderTriangle, order::Vector{Int})
    @assert length(order)==2
    d = domain(K)
    if order==[1,0] || order==[0,1]
        if d == Triangle()
            ConcreteDerivative(K,order)
        else
            if order == [1,0]
                M_x,M_y = tocanonicalD(d)[:,1]
            else
                M_x,M_y = tocanonicalD(d)[:,2]
            end
            K_c = setcanonicaldomain(K)
            D_x,D_y = Derivative(K_c,[1,0]),Derivative(K_c,[0,1])
            L = M_x*D_x + M_y*D_y
            DerivativeWrapper(SpaceOperator(L,K,setdomain(rangespace(L), d)),order)
        end
    elseif order[1]>1
        D=Derivative(K,[1,0])
        DerivativeWrapper(TimesOperator(Derivative(rangespace(D),[order[1]-1,order[2]]),D),order)
    else
        @assert order[2]≥1
        D=Derivative(K,[0,1])
        DerivativeWrapper(TimesOperator(Derivative(rangespace(D),[order[1],order[2]-1]),D),order)
    end
end


rangespace(D::ConcreteDerivative{KoornwinderTriangle}) =
    KoornwinderTriangle(D.space.α+D.order[1],
                        D.space.β+D.order[2],
                        D.space.γ+sum(D.order),
                        domain(D))


isbandedblockbanded(::ConcreteDerivative{KoornwinderTriangle}) = true


blockbandinds(D::ConcreteDerivative{KoornwinderTriangle}) = 0,sum(D.order)
subblockbandinds(D::ConcreteDerivative{KoornwinderTriangle}) = (0,sum(D.order))
subblockbandinds(D::ConcreteDerivative{KoornwinderTriangle},k::Integer) = k==1 ? 0 : sum(D.order)

function getindex(D::ConcreteDerivative{KoornwinderTriangle},k::Integer,j::Integer)
    T=eltype(D)
    S=domainspace(D)
    α,β,γ = S.α,S.β,S.γ
    K = Int(block(rangespace(D),k))
    J = Int(block(S,j))
    κ=k-blockstart(rangespace(D),K)+1
    ξ=j-blockstart(S,J)+1

    if D.order==[0,1]
        if J==K+1 && κ+1 == ξ
            T(1+κ+β+γ)
        else
            zero(T)
        end
    elseif D.order==[1,0]
        if J == K+1 && κ == ξ
            T((1+κ+K+α+β+γ)*(κ+γ+β)/(2κ+γ+β-1))
        elseif J == K+1 && κ+1 == ξ
            T((κ+β)*(κ+K+γ+β+1)/(2κ+γ+β+1))
        else
            zero(T)
        end
    else
        error("Not implemented")
    end
end

function Base.convert{T}(::Type{BandedBlockBandedMatrix},
        S::SubOperator{T,ConcreteDerivative{KoornwinderTriangle,Vector{Int},T},
                                                                        Tuple{BlockRange1,BlockRange1}})
    ret = BandedBlockBandedMatrix(Zeros,S)
    D = parent(S)
    sp=domainspace(D)
    α,β,γ = sp.α,sp.β,sp.γ
    K_sh = first(parentindexes(S)[1])-1
    J_sh = first(parentindexes(S)[2])-1
    N,M=nblocks(ret)::Tuple{Int,Int}

    if D.order == [1,0]
        for K=Block.(1:N)
            J = K+K_sh-J_sh+1
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,K,J)
                KK = size(bl,1)
                @inbounds for κ=1:KK
                    bl[κ,κ] = (1+κ+KK+α+β+γ)*(κ+γ+β)/(2κ+γ+β-1)
                    bl[κ,κ+1] = (κ+β)*(κ+KK+γ+β+1)/(2κ+γ+β+1)
                end
            end
        end
    elseif D.order == [0,1]
        for K=Block.(1:N)
            J = K+K_sh-J_sh+1
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,K,J)
                KK = size(bl,1)
                @inbounds for κ=1:KK
                    bl[κ,κ+1] = 1+κ+β+γ
                end
            end
        end
    end
    ret
end



## Conversion

function union_rule(K1::KoornwinderTriangle,K2::KoornwinderTriangle)
    if domain(K1) == domain(K2)
        KoornwinderTriangle(min(K1.α,K2.α),min(K1.β,K2.β),min(K1.γ,K2.γ))
    else
        K1 ⊕ K2
    end
end
function conversion_rule(K1::KoornwinderTriangle,K2::KoornwinderTriangle)
    if domain(K1) == domain(K2)
        KoornwinderTriangle(min(K1.α,K2.α),min(K1.β,K2.β),min(K1.γ,K2.γ),domain(K1))
    else
        NoSpace()
    end
end
function maxspace_rule(K1::KoornwinderTriangle, K2::KoornwinderTriangle)
    if domain(K1) == domain(K2)
        KoornwinderTriangle(max(K1.α,K2.α),max(K1.β,K2.β),max(K1.γ,K2.γ), domain(K1))
    else
        NoSpace()
    end
end

function Conversion(K1::KoornwinderTriangle,K2::KoornwinderTriangle)
    @assert K1.α≤K2.α && K1.β≤K2.β && K1.γ≤K2.γ &&
        isapproxinteger(K1.α-K2.α) && isapproxinteger(K1.β-K2.β) &&
        isapproxinteger(K1.γ-K2.γ)

    if (K1.α==K2.α && K1.β==K2.β && K1.γ==K2.γ)
        ConversionWrapper(eye(K1))
    elseif (K1.α+1==K2.α && K1.β==K2.β && K1.γ==K2.γ) ||
            (K1.α==K2.α && K1.β+1==K2.β && K1.γ==K2.γ) ||
            (K1.α==K2.α && K1.β==K2.β && K1.γ+1==K2.γ)
        ConcreteConversion(K1,K2)
    elseif K1.α+1<K2.α || (K1.α+1==K2.α && (K1.β+1≥K2.β || K1.γ+1≥K2.γ))
        # increment α if we have e.g. (α+2,β,γ) or  (α+1,β+1,γ)
        Conversion(K1,KoornwinderTriangle(K1.α+1,K1.β,K1.γ),K2)
    elseif K1.β+1<K2.β || (K1.β+1==K2.β && K1.γ+1≥K2.γ)
        # increment β
        Conversion(K1,KoornwinderTriangle(K1.α,K1.β+1,K1.γ),K2)
    elseif K1.γ+1<K2.γ
        # increment γ
        Conversion(K1,KoornwinderTriangle(K1.α,K1.β,K1.γ+1),K2)
    else
        error("There is a bug: cannot convert $K1 to $K2")
    end
end


isbandedblockbanded(::ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle}) = true


blockbandinds(C::ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle}) = (0,1)

subblockbandinds(C::ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle}) = (0,1)
subblockbandinds(C::ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle},k::Integer) = k==1 ? 0 : 1



function getindex(C::ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle,T},k::Integer,j::Integer) where T
    K1=domainspace(C);K2=rangespace(C)
    α,β,γ = K1.α,K1.β,K1.γ
    K = Int(block(K2,k))
    J = Int(block(K1,j))
    κ=k-blockstart(K2,K)+1
    ξ=j-blockstart(K1,J)+1

    if K2.α == α+1 && K2.β == β && K2.γ == γ
        if     K == J    && κ == ξ
            T((J+ξ+α+β+γ)/(2J+α+β+γ))
        elseif J == K+1  && κ == ξ
            T((J+ξ+β+γ-1)/(2J+α+β+γ))
        else
            zero(T)
        end
    elseif K2.α==α && K2.β==β+1 && K2.γ==γ
        if  J == K == κ == ξ == 1
            one(T)
        elseif   J == K   && κ == ξ
            if β+γ == -1 && κ == 1
                T((K+κ+α+β+γ)/(2K+α+β+γ))
            else
                T((K+κ+α+β+γ)/(2K+α+β+γ)*(κ+β+γ)/(2κ+β+γ-1))
            end
        elseif J == K   && κ+1 == ξ
            T(-(κ+γ)/(2κ+β+γ+1)*(K-κ)/(2K+α+β+γ))
        elseif J == K+1 && κ == ξ
            if β+γ == -1 && κ == 1
                T(-(K-κ+α+1)/(2K+α+β+γ+2))
            else
                T(-(K-κ+α+1)/(2K+α+β+γ+2)*(κ+β+γ)/(2κ+β+γ-1))
            end
        elseif J == K+1 && κ+1 == ξ
            T((κ+γ)/(2κ+β+γ+1)*(K+κ+β+γ+1)/(2K+α+β+γ+2))
        else
            zero(T)
        end
    elseif K2.α==α && K2.β==β && K2.γ==γ+1
        if K == J && κ == ξ
            if β+γ == -1 && κ == 1
                T((K+κ+α+β+γ)/(2K+α+β+γ))
            else
                T((K+κ+α+β+γ)/(2K+α+β+γ)*(κ+β+γ)/(2κ+β+γ-1))
            end
        elseif K == J && κ+1 == ξ
            T((κ+β)/(2κ+β+γ+1)*(K-κ)/(2K+α+β+γ))
        elseif J == K+1 && κ == ξ
            if β+γ == -1 && κ == 1
                T(-(K-κ+α+1)/(2K+α+β+γ+2))
            else
                T(-(K-κ+α+1)/(2K+α+β+γ+2)*(κ+β+γ)/(2κ+β+γ-1))
            end
        elseif J == K+1 && κ+1 == ξ
            T(-(κ+β)/(2κ+β+γ+1)*(K+κ+β+γ+1)/(2K+α+β+γ+2))
        else
            zero(T)
        end
    else
        error("Not implemented")
    end
end


function Base.convert(::Type{BandedBlockBandedMatrix},S::SubOperator{T,ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle,T},
                                                                        Tuple{BlockRange1,BlockRange1}}) where T
    ret = BandedBlockBandedMatrix(Zeros,S)
    K1=domainspace(parent(S))
    K2=rangespace(parent(S))
    α,β,γ = K1.α,K1.β,K1.γ
    K_sh = first(parentindexes(S)[1])-1
    J_sh = first(parentindexes(S)[2])-1
    N,M=nblocks(ret)::Tuple{Int,Int}

    if K2.α == α+1 && K2.β == β && K2.γ == γ
        for KK=Block.(1:N)
            JJ = KK+K_sh-J_sh  # diagonal
            if 1 ≤ Int(JJ) ≤ M
                bl = view(ret,KK,JJ)
                J = size(bl,2)
                @inbounds for ξ=1:J
                    bl[ξ,ξ] = (J+ξ+α+β+γ)/(2J+α+β+γ)
                end
            end
            JJ = KK+K_sh-J_sh+1  # super-diagonal
            if 1 ≤ Int(JJ) ≤ M
                bl = view(ret,KK,JJ)
                J = size(bl,2)
                @inbounds for ξ=1:J-1
                    bl[ξ,ξ] = (J+ξ+β+γ-1)/(2J+α+β+γ)
                end
            end
        end
    elseif K2.α==α && K2.β==β+1 && K2.γ==γ && β+γ==-1
        for KK=Block.(1:N)
            J = KK+K_sh-J_sh  # diagonal
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,KK,J)
                K = size(bl,1)
                s = (2K+α+β+γ)
                bl[1,1] = (K+1+α+β+γ)/s
                @inbounds for κ=2:K
                    bl[κ,κ] = (K+κ+α+β+γ)/s*(κ+β+γ)/(2κ+β+γ-1)
                end
                @inbounds for κ=1:K-1
                    bl[κ,κ+1] = -(κ+γ)/(2κ+β+γ+1)*(K-κ)/(2K+α+β+γ)
                end
            end
            J = KK+K_sh-J_sh+1  # super-diagonal
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,KK,J)
                K = size(bl,1)
                bl[1,1] = -(K-1+α+1)/(2K+α+β+γ+2)
                @inbounds for κ=2:K
                    bl[κ,κ] = -(K-κ+α+1)/(2K+α+β+γ+2)*(κ+β+γ)/(2κ+β+γ-1)
                end
                @inbounds for κ=1:K
                    bl[κ,κ+1] = (κ+γ)/(2κ+β+γ+1)*(K+κ+β+γ+1)/(2K+α+β+γ+2)
                end
            end
        end
    elseif K2.α==α && K2.β==β+1 && K2.γ==γ
        for KK=Block.(1:N)
            J = KK+K_sh-J_sh  # diagonal
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,KK,J)
                K = size(bl,1)
                s = (2K+α+β+γ)
                @inbounds for κ=1:K
                    bl[κ,κ] = (K+κ+α+β+γ)/s*(κ+β+γ)/(2κ+β+γ-1)
                end
                @inbounds for κ=1:K-1
                    bl[κ,κ+1] = -(κ+γ)/(2κ+β+γ+1)*(K-κ)/(2K+α+β+γ)
                end
            end
            J = KK+K_sh-J_sh+1  # super-diagonal
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,KK,J)
                K = size(bl,1)
                @inbounds for κ=1:K
                    bl[κ,κ] = -(K-κ+α+1)/(2K+α+β+γ+2)*(κ+β+γ)/(2κ+β+γ-1)
                    bl[κ,κ+1] = (κ+γ)/(2κ+β+γ+1)*(K+κ+β+γ+1)/(2K+α+β+γ+2)
                end
            end
        end
    elseif K2.α==α && K2.β==β && K2.γ==γ+1  && β+γ==-1
        for KK = Block.(1:N)
            J = KK+K_sh-J_sh  # diagonal
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,KK,J)
                K = size(bl,1)
                s = (2K+α+β+γ)
                bl[1,1] = (K+1+α+β+γ)/s
                @inbounds for κ=2:K
                    bl[κ,κ] = (K+κ+α+β+γ)/s*(κ+β+γ)/(2κ+β+γ-1)
                end
                @inbounds for κ=1:K-1
                   bl[κ,κ+1] = (κ+β)/(2κ+β+γ+1)*(K-κ)/s
               end
            end
            J = KK+K_sh-J_sh+1  # super-diagonal
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,KK,J)
                K = size(bl,1)
                s = (2K+α+β+γ+2)
                bl[1,1] = -(K+α)/s
                @inbounds for κ=2:K
                    bl[κ,κ] = -(K-κ+α+1)/s*(κ+β+γ)/(2κ+β+γ-1)
                end
                @inbounds for κ=1:K
                    bl[κ,κ+1] = -(κ+β)/(2κ+β+γ+1)*(K+κ+β+γ+1)/s
                end
            end
        end
    elseif K2.α==α && K2.β==β && K2.γ==γ+1
        for KK = Block.(1:N)
            J = KK+K_sh-J_sh  # diagonal
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,KK,J)
                K = size(bl,1)
                @inbounds for κ=1:K
                    bl[κ,κ] = (K+κ+α+β+γ)/(2K+α+β+γ)*(κ+β+γ)/(2κ+β+γ-1)
                end
                @inbounds for κ=1:K-1
                   bl[κ,κ+1] = (κ+β)/(2κ+β+γ+1)*(K-κ)/(2K+α+β+γ)
               end
            end
            J = KK+K_sh-J_sh+1  # super-diagonal
            if 1 ≤ Int(J) ≤ M
                bl = view(ret,KK,J)
                K = size(bl,1)
                @inbounds for κ=1:K
                    bl[κ,κ] = -(K-κ+α+1)/(2K+α+β+γ+2)*(κ+β+γ)/(2κ+β+γ-1)
                    bl[κ,κ+1] = -(κ+β)/(2κ+β+γ+1)*(K+κ+β+γ+1)/(2K+α+β+γ+2)
                end
            end
        end
    end
    ret
end



## Jacobi Operators

# k is 1, 2, ... for x, y, z,...
immutable Lowering{k,S,T} <: Operator{T}
    space::S
end

Base.convert{k}(::Type{Lowering{k}},sp) = Lowering{k,typeof(sp),prectype(sp)}(sp)
Base.convert{x,T,S}(::Type{Operator{T}},J::Lowering{x,S}) = Lowering{x,S,T}(J.space)


domainspace(R::Lowering) = R.space

isbandedblockbanded(::Lowering) = true

blockbandinds(::Lowering) = (-1,0)

subblockbandinds(::Lowering{1,KoornwinderTriangle}) = (0,0)
subblockbandinds(::Lowering{2,KoornwinderTriangle}) = (-1,0)
subblockbandinds(::Lowering{3,KoornwinderTriangle}) = (-1,0)

subblockbandinds(::Lowering{1,KoornwinderTriangle},k::Integer) = 0
subblockbandinds(::Lowering{2,KoornwinderTriangle},k::Integer) = k==1 ? -1 : 0
subblockbandinds(::Lowering{3,KoornwinderTriangle},k::Integer) = k==1 ? -1 : 0


rangespace(R::Lowering{1,KoornwinderTriangle}) =
    KoornwinderTriangle(R.space.α-1,R.space.β,R.space.γ,domain(domainspace(R)))
rangespace(R::Lowering{2,KoornwinderTriangle}) =
    KoornwinderTriangle(R.space.α,R.space.β-1,R.space.γ,domain(domainspace(R)))
rangespace(R::Lowering{3,KoornwinderTriangle}) =
    KoornwinderTriangle(R.space.α,R.space.β,R.space.γ-1,domain(domainspace(R)))


function getindex{T}(R::Lowering{1,KoornwinderTriangle,T},k::Integer,j::Integer)
    α,β,γ=R.space.α,R.space.β,R.space.γ
    K = Int(block(rangespace(R),k))
    J = Int(block(domainspace(R),j))
    κ = k-blockstart(rangespace(R),K)+1
    ξ = j-blockstart(domainspace(R),J)+1

    s = 2J+α+β+γ

    if K == J && κ == ξ
        T((J-ξ+α)/s)
    elseif K == J+1 && κ == ξ
        T((J-ξ+1)/s)
    else
        zero(T)
    end
end


function getindex(R::Lowering{2,KoornwinderTriangle,T},k::Integer,j::Integer) where T
    α,β,γ=R.space.α,R.space.β,R.space.γ
    K = Int(block(rangespace(R),k))
    J = Int(block(domainspace(R),j))
    κ = k-blockstart(rangespace(R),K)+1
    ξ = j-blockstart(domainspace(R),J)+1

    s = (2ξ-1+β+γ)*(2J+α+β+γ)

    if K == J && κ == ξ
        T((ξ-1+β)*(J+ξ+β+γ-1)/s)
    elseif K == J && κ == ξ+1
        T(-ξ*(J-ξ+α)/s)
    elseif K == J+1 && κ == ξ
        T(-(ξ-1+β)*(J-ξ+1)/s)
    elseif K == J+1 && κ == ξ+1
        T(ξ*(J+ξ+α+β+γ)/s)
    else
        zero(T)
    end
end

function getindex(R::Lowering{3,KoornwinderTriangle,T},k::Integer,j::Integer) where T
    α,β,γ=R.space.α,R.space.β,R.space.γ
    K = Int(block(rangespace(R),k))
    J = Int(block(domainspace(R),j))
    κ=k-blockstart(rangespace(R),K)+1
    ξ=j-blockstart(domainspace(R),J)+1

    s = (2ξ+β+γ-1)*(2J+α+β+γ)

    if K==J && κ == ξ
        T((ξ-1+γ)*(J+ξ+β+γ-1)/s)
    elseif K==J && κ == ξ+1
        T(ξ*(J-ξ+α)/s)
    elseif K==J+1 && κ == ξ
        T(-(ξ-1+γ)*(J-ξ+1)/s)
    elseif K==J+1 && κ == ξ+1
        T(-ξ*(J+ξ+α+β+γ)/s)
    else
        zero(T)
    end
end


function Base.convert(::Type{BandedBlockBandedMatrix},S::SubOperator{T,Lowering{1,KoornwinderTriangle,T},
                                                                        Tuple{BlockRange1,BlockRange1}}) where T
    ret = BandedBlockBandedMatrix(Zeros, S)
    R = parent(S)
    α,β,γ=R.space.α,R.space.β,R.space.γ
    K_sh = first(parentindexes(S)[1])-1
    J_sh = first(parentindexes(S)[2])-1
    N,M=nblocks(ret)::Tuple{Int,Int}

    for KK=Block.(1:N)
        JJ = KK+K_sh-J_sh-1  # super-diagonal
        if 1 ≤ Int(JJ) ≤ M
            bl = view(ret,KK,JJ)
            J = size(bl,2)
            s = 2J+α+β+γ
            @inbounds for ξ=1:J
                bl[ξ,ξ] = (J-ξ+1)/s
            end
        end
        JJ = KK+K_sh-J_sh  # diagonal
        if 1 ≤ Int(JJ) ≤ M
            bl = view(ret,KK,JJ)
            J = size(bl,2)
            s = 2J+α+β+γ
            @inbounds for ξ=1:J
                bl[ξ,ξ] = (J-ξ+α)/s
            end
        end
    end
    ret
end


function Base.convert{T}(::Type{BandedBlockBandedMatrix},S::SubOperator{T,Lowering{2,KoornwinderTriangle,T},
                                                                        Tuple{BlockRange1,BlockRange1}})
    ret = BandedBlockBandedMatrix(Zeros,S)
    R = parent(S)
    α,β,γ=R.space.α,R.space.β,R.space.γ
    K_sh = first(parentindexes(S)[1])-1
    J_sh = first(parentindexes(S)[2])-1
    N,M = nblocks(ret)::Tuple{Int,Int}


    for KK=Block.(1:N)
        JJ = KK+K_sh-J_sh-1  # super-diagonal
        if 1 ≤ Int(JJ) ≤ M
            bl = view(ret,KK,JJ)
            J = size(bl,2)

            @inbounds for ξ=1:J
                s = (2ξ-1+β+γ)*(2J+α+β+γ)
                bl[ξ,ξ] = -(ξ-1+β)*(J-ξ+1)/s
                bl[ξ+1,ξ] = ξ*(J+ξ+α+β+γ)/s
            end
        end
        JJ = KK+K_sh-J_sh  # diagonal
        if 1 ≤ Int(JJ) ≤ M
            bl = view(ret,KK,JJ)
            J = size(bl,2)
            @inbounds for ξ=1:J
                s = (2ξ-1+β+γ)*(2J+α+β+γ)
                bl[ξ,ξ] = (ξ-1+β)*(J+ξ+β+γ-1)/s
                if ξ < J
                    bl[ξ+1,ξ] = -ξ*(J-ξ+α)/s
                end
            end
        end
    end
    ret
end

function Base.convert{T}(::Type{BandedBlockBandedMatrix},S::SubOperator{T,Lowering{3,KoornwinderTriangle,T},
                                                                        Tuple{BlockRange1,BlockRange1}})
    ret = BandedBlockBandedMatrix(Zeros,S)
    R = parent(S)
    α,β,γ=R.space.α,R.space.β,R.space.γ
    K_sh = first(parentindexes(S)[1])-1
    J_sh = first(parentindexes(S)[2])-1
    N,M=nblocks(ret)::Tuple{Int,Int}

    for KK=Block.(1:N)
        JJ = KK+K_sh-J_sh-1  # super-diagonal
        if 1 ≤ Int(JJ) ≤ M
            bl = view(ret,KK,JJ)
            J = size(bl,2)

            @inbounds for ξ=1:J
                s = (2ξ-1+β+γ)*(2J+α+β+γ)
                bl[ξ,ξ] = -(ξ-1+γ)*(J-ξ+1)/s
                bl[ξ+1,ξ] = -ξ*(J+ξ+α+β+γ)/s
            end
        end
        JJ = KK+K_sh-J_sh  # diagonal
        if 1 ≤ Int(JJ) ≤ M
            bl = view(ret,KK,JJ)
            J = size(bl,2)
            @inbounds for ξ=1:J
                s = (2ξ-1+β+γ)*(2J+α+β+γ)
                bl[ξ,ξ] = (ξ-1+γ)*(J+ξ+β+γ-1)/s
                if ξ < J
                    bl[ξ+1,ξ] = ξ*(J-ξ+α)/s
                end
            end
        end
    end
    ret
end


### Weighted

immutable TriangleWeight{S} <: WeightSpace{S,Triangle,Float64}
    α::Float64
    β::Float64
    γ::Float64
    space::S

    TriangleWeight{S}(α::Number,β::Number,γ::Number,sp::S) where S =
        new(Float64(α),Float64(β),Float64(γ),sp)
end

TriangleWeight(α::Number,β::Number,γ::Number,sp::Space) =
    TriangleWeight{typeof(sp)}(α,β,γ,sp)

WeightedTriangle(α::Number,β::Number,γ::Number) =
    TriangleWeight(α,β,γ,KoornwinderTriangle(α,β,γ))

triangleweight(S,x,y) = x.^S.α.*y.^S.β.*(1-x-y).^S.γ
triangleweight(S,xy::Vec) = triangleweight(S,xy...)


weight(S::TriangleWeight,x,y) = triangleweight(S,tocanonical(S,x,y))
weight(S::TriangleWeight,xy::Vec) = weight(S,xy...)

setdomain(K::TriangleWeight, d::Triangle) = TriangleWeight(K.α,K.β,K.γ,setdomain(K.space,d))

immutable TriangleWeightEvaluatePlan{S,PP}
    space::S
    plan::PP
end

plan_evaluate{SS}(f::Fun{TriangleWeight{SS}},xy...) =
    TriangleWeightEvaluatePlan(space(f),
        plan_evaluate(Fun(space(f).space,coefficients(f)),xy...))

(P::TriangleWeightEvaluatePlan)(xy...) =
    weight(P.space,xy...)*P.plan(xy...)


itransform(S::TriangleWeight,cfs::Vector) =
    plan_evaluate(Fun(S,cfs)).(points(S,length(cfs)))

#TODO: Move to Singulariaties.jl
for func in (:blocklengths,:tensorizer)
    @eval $func(S::TriangleWeight) = $func(S.space)
end

for OP in (:block,:blockstart,:blockstop)
    @eval $OP(s::TriangleWeight,M::Integer) = $OP(s.space,M)
end


spacescompatible(A::TriangleWeight,B::TriangleWeight) = A.α ≈ B.α && A.β ≈ B.β && A.γ ≈ B.γ &&
                                                        spacescompatible(A.space,B.space)




function conversion_rule(A::TriangleWeight,B::TriangleWeight)
    if isapproxinteger(A.α-B.α) && isapproxinteger(A.β-B.β) && isapproxinteger(A.γ-B.γ)
        ct=conversion_type(A.space,B.space)
        ct==NoSpace() ? NoSpace() : TriangleWeight(max(A.α,B.α),max(A.β,B.β),max(A.γ,B.γ),ct)
    else
        NoSpace()
    end
end

function maxspace_rule(A::TriangleWeight,B::TriangleWeight)
    if isapproxinteger(A.α-B.α) && isapproxinteger(A.β-B.β) && isapproxinteger(A.γ-B.γ)
        ms=maxspace(A.space,B.space)
        if min(A.α,B.α)==0.0 && min(A.β,B.β) == 0.0 && min(A.γ,B.γ) == 0.0
            return ms
        else
            return TriangleWeight(min(A.α,B.α),min(A.β,B.β),min(A.γ,B.γ),ms)
        end
    end
    NoSpace()
end

function maxspace_rule(A::TriangleWeight{<:KoornwinderTriangle},B::TriangleWeight{<:KoornwinderTriangle})
    if domain(A) == domain(B) && isapproxinteger(A.α-B.α) && isapproxinteger(A.β-B.β) && isapproxinteger(A.γ-B.γ)
        α = min(A.α,B.α)
        β = min(A.β,B.β)
        γ = min(A.γ,B.γ)
        d = domain(A)
        A_lowered = KoornwinderTriangle(A.space.α+α-A.α, A.space.β+β-A.β, A.space.γ+γ-A.γ,d)
        B_lowered = KoornwinderTriangle(B.space.α+α-B.α, B.space.β+β-B.β, B.space.γ+γ-B.γ,d)
        ms = maxspace(A_lowered,B_lowered)
        α == β == γ == 0 ? ms : TriangleWeight(α,β,γ,ms)
    else
        NoSpace()
    end
end

maxspace_rule(A::TriangleWeight,B::KoornwinderTriangle) = maxspace(A,TriangleWeight(0.,0.,0.,B))

conversion_rule(A::TriangleWeight,B::KoornwinderTriangle) = conversion_type(A,TriangleWeight(0.,0.,0.,B))

function Conversion(A::TriangleWeight{<:KoornwinderTriangle}, B::TriangleWeight{<:KoornwinderTriangle})
    @assert isapproxinteger(A.α-B.α) && isapproxinteger(A.β-B.β) && isapproxinteger(A.γ-B.γ)
    @assert A.α ≥ B.α && A.β ≥ B.β && A.γ ≥ B.γ

    if A.α ≈ B.α && A.β ≈ B.β && A.γ ≈ B.γ
        ConversionWrapper(SpaceOperator(Conversion(A.space,B.space),A,B))
    elseif A.α ≈ B.α+1 && A.β ≈ B.β && A.γ ≈ B.γ &&
           A.space.α ≈ B.space.α+1 && A.space.β ≈ B.space.β && A.space.γ ≈ B.space.γ
        ConversionWrapper(SpaceOperator(Lowering{1}(A.space),A,B))
    elseif A.α ≈ B.α && A.β ≈ B.β+1 && A.γ ≈ B.γ &&
           A.space.α ≈ B.space.α && A.space.β ≈ B.space.β+1 && A.space.γ ≈ B.space.γ
        ConversionWrapper(SpaceOperator(Lowering{2}(A.space),A,B))
    elseif A.α ≈ B.α && A.β ≈ B.β && A.γ ≈ B.γ+1 &&
           A.space.α ≈ B.space.α && A.space.β ≈ B.space.β && A.space.γ ≈ B.space.γ+1
        ConversionWrapper(SpaceOperator(Lowering{3}(A.space),A,B))
    elseif A.α ≈ B.α+1 && A.β ≈ B.β && A.γ ≈ B.γ
        Jx = Lowering{1}(A.space)
        C = Conversion(rangespace(Jx),B.space)
        ConversionWrapper(SpaceOperator(C*Jx,A,B))
    elseif A.α ≈ B.α && A.β ≈ B.β+1 && A.γ ≈ B.γ
        Jy = Lowering{2}(A.space)
        C = Conversion(rangespace(Jy),B.space)
        ConversionWrapper(SpaceOperator(C*Jy,A,B))
    elseif A.α ≈ B.α && A.β ≈ B.β && A.γ ≈ B.γ+1
        Jz = Lowering{3}(A.space)
        C = Conversion(rangespace(Jz),B.space)
        ConversionWrapper(SpaceOperator(C*Jz,A,B))
    elseif A.α ≥ B.α+1
        Conversion(A,TriangleWeight(A.α-1,A.β,A.γ,
                                    KoornwinderTriangle(A.space.α-1,A.space.β,A.space.γ)),B)
    elseif A.β ≥ B.β+1
        Conversion(A,TriangleWeight(A.α,A.β-1,A.γ,
                                        KoornwinderTriangle(A.space.α,A.space.β-1,A.space.γ)),B)
    elseif A.γ ≥ B.γ+1
        Conversion(A,TriangleWeight(A.α,A.β,A.γ-1,
                                        KoornwinderTriangle(A.space.α,A.space.β,A.space.γ-1)),B)
    else
        error("Somethings gone wrong!")
    end
end

Conversion(A::TriangleWeight,B::KoornwinderTriangle) =
    ConversionWrapper(SpaceOperator(
        Conversion(A,TriangleWeight(0.,0.,0.,B)),
        A,B))


function triangleweight_Derivative(S::TriangleWeight,order)
    if S.α == S.β == S.γ == 0
        D=Derivative(S.space,order)
        SpaceOperator(D,S,rangespace(D))
    elseif S.α == S.β == S.γ == S.space.α == S.space.β == S.space.γ == 1
        C=Conversion(S,KoornwinderTriangle(0,0,0))
        D = Derivative(rangespace(C),order)
        SpaceOperator(D*C,S,rangespace(D))
    elseif order[2] == 0 && S.α == 0 && S.γ == 0
        Dx = Derivative(S.space,order)
        DerivativeWrapper(
            SpaceOperator(Dx,S,TriangleWeight(S.α,S.β,S.γ,rangespace(Dx))),
            order)
    elseif order[1] == 0 && S.β == 0 && S.γ == 0
        Dy = Derivative(S.space,order)
        DerivativeWrapper(
            SpaceOperator(Dy,S,TriangleWeight(S.α,S.β,S.γ,rangespace(Dy))),
            order)
    elseif order == [1,0] && S.α == 0
        Dx = Derivative(S.space,order)
        Jx = Lowering{1}(rangespace(Dx))
        Jy = Lowering{2}(rangespace(Dx))
        A = -S.γ*I + (I-Jx-Jy)*Dx
        DerivativeWrapper(
            SpaceOperator(A,S,TriangleWeight(S.α,S.β,S.γ-1,rangespace(A))),
            order)
    elseif order == [1,0] && S.γ == 0
        Dx = Derivative(S.space,order)
        Jx = Lowering{1}(rangespace(Dx))
        A = S.α*I + Jx*Dx
        DerivativeWrapper(
            SpaceOperator(A,S,TriangleWeight(S.α-1,S.β,S.γ,rangespace(A))),
            order)
    elseif order == [1,0]
        Dx = Derivative(S.space,order)
        Jx = Lowering{1}(rangespace(Dx))
        Jy = Lowering{2}(rangespace(Dx))
        A = S.α*(I-Jx-Jy) - S.γ*Jx + Jx*(I-Jx-Jy)*Dx
        DerivativeWrapper(
            SpaceOperator(A,S,TriangleWeight(S.α-1,S.β,S.γ-1,rangespace(A))),
            order)
    elseif order == [0,1] && S.β == 0
        Dy = Derivative(S.space,order)
        Jx = Lowering{1}(rangespace(Dy))
        Jy = Lowering{2}(rangespace(Dy))
        A = -S.γ*I + (I-Jx-Jy)*Dy
        DerivativeWrapper(
            SpaceOperator(A,S,TriangleWeight(S.α,S.β,S.γ-1,rangespace(A))),
            order)
    elseif order == [0,1] && S.γ == 0
        Dy = Derivative(S.space,order)
        Jy = Lowering{2}(rangespace(Dy))
        A = S.β*I + Jy*Dy
        DerivativeWrapper(
            SpaceOperator(A,S,TriangleWeight(S.α,S.β-1,S.γ,rangespace(A))),
            order)
    elseif order == [0,1]
        Dy = Derivative(S.space,order)
        Jx = Lowering{1}(rangespace(Dy))
        Jy = Lowering{2}(rangespace(Dy))
        A = S.β*(I-Jx-Jy) - S.γ*Jy + Jy*(I-Jx-Jy)*Dy
        DerivativeWrapper(
            SpaceOperator(A,S,TriangleWeight(S.α,S.β-1,S.γ-1,rangespace(A))),
            order)
    elseif order[1] > 1
        D=Derivative(S,[1,0])
        DerivativeWrapper(TimesOperator(Derivative(rangespace(D),[order[1]-1,order[2]]),D),order)
    else
        @assert order[2] > 1
        D=Derivative(S,[0,1])
        DerivativeWrapper(TimesOperator(Derivative(rangespace(D),[order[1],order[2]-1]),D),order)
    end
end

function Derivative(S::TriangleWeight{KoornwinderTriangle},order)
    if S.α == 0 && S.β == 0 && S.γ == 0
        D = Derivative(S.space,order)
        DerivativeWrapper(SpaceOperator(D,S,rangespace(D)),order)
    elseif (order[1] ≥ 1 &&  (S.α == 0 || S.γ == 0) ) ||
            (order[2] ≥ 1 &&  (S.β == 0 || S.γ == 0))
        C = Conversion(S,KoornwinderTriangle(0,0,0))
        DerivativeWrapper(Derivative(rangespace(C),order)*C,order)
    elseif S.α == S.space.α && S.β == S.space.β && S.γ == S.space.γ
        if order == [1,0] || order == [0,1]
            d = domain(S)
            if d == Triangle()
                ConcreteDerivative(S,order)
            else
                if order == [1,0]
                    M_x,M_y = tocanonicalD(d)[:,1]
                else
                    M_x,M_y = tocanonicalD(d)[:,2]
                end
                K_c = setcanonicaldomain(S)
                D_x,D_y = Derivative(K_c,[1,0]),Derivative(K_c,[0,1])
                L = M_x*D_x + M_y*D_y
                DerivativeWrapper(SpaceOperator(L,S,setdomain(rangespace(L), d)),order)
            end
        elseif order[1] ≥ 1
            D1 = Derivative(S,[1,0])
            DerivativeWrapper(TimesOperator(Derivative(rangespace(D1),[order[1]-1,order[2]]),D1),order)
        else #order[2] ≥ 1
            D2 = Derivative(S,[0,1])
            DerivativeWrapper(TimesOperator(Derivative(rangespace(D2),[order[1],order[2]-1]),D2),order)
        end
    else
        triangleweight_Derivative(S,order)
    end
end
Derivative(S::TriangleWeight,order) = triangleweight_Derivative(S,order)


rangespace(D::ConcreteDerivative{TriangleWeight{KoornwinderTriangle}}) =
    WeightedTriangle(D.space.α-D.order[1],D.space.β-D.order[2],D.space.γ-1)

isbandedblockbanded(::ConcreteDerivative{TriangleWeight{KoornwinderTriangle}}) = true

blockbandinds(::ConcreteDerivative{TriangleWeight{KoornwinderTriangle}}) = (-1,0)
subblockbandinds(D::ConcreteDerivative{TriangleWeight{KoornwinderTriangle}}) =
    (-1,0)  #TODO: subblockbandinds (-1,-1) for Dy
subblockbandinds(D::ConcreteDerivative{TriangleWeight{KoornwinderTriangle}},k::Integer) =
    k==1 ? -1 : 0  #TODO: subblockbandinds (-1,-1) for Dy


function getindex{OT,T}(D::ConcreteDerivative{TriangleWeight{KoornwinderTriangle},OT,T},k::Integer,j::Integer)::T
    α,β,γ=D.space.α,D.space.β,D.space.γ
    K = Int(block(rangespace(D),k))
    J = Int(block(domainspace(D),j))
    κ=k-blockstart(rangespace(D),K)+1
    ξ=j-blockstart(domainspace(D),J)+1

    if D.order[1] == 1
        K == J+1 && ξ == κ && return -T((ξ+γ-1)*(J-ξ+1))/(2ξ+β+γ-1)
        K == J+1 && ξ+1 == κ && return -T(ξ*(J-ξ+α))/(2ξ+β+γ-1)
    else
        @assert D.order[2] == 1
        K == J+1 && ξ+1 == κ && return T(-ξ)
    end

    zero(T)
end






## Multiplication Operators
function operator_clenshaw2D{T}(Jx,Jy,cfs::Vector{Vector{T}},x,y)
    N=length(cfs)
    S = domainspace(x)
    Z=ZeroOperator(S,S)
    bk1=Array(Operator{T},N+1);bk1[:]=Z
    bk2=Array(Operator{T},N+2);bk2[:]=Z

    Abk1x=Array(Operator{T},N+1);Abk1x[:]=Z
    Abk1y=Array(Operator{T},N+1);Abk1y[:]=Z
    Abk2x=Array(Operator{T},N+1);Abk2x[:]=Z
    Abk2y=Array(Operator{T},N+1);Abk2y[:]=Z

    for K=Block(N):-1:Block(2)
        Bx,By=view(Jx,K,K),view(Jy,K,K)
        Cx,Cy=view(Jx,K,K+1),view(Jy,K,K+1)
        JxK=view(Jx,K+1,K)
        JyK=view(Jy,K+1,K)
        @inbounds for k=1:Int(K)
            bk1[k] /= JxK[k,k]
        end

        bk1[Int(K)-1] -= JyK[Int(K)-1,end]/(JxK[Int(K)-1,Int(K)-1]*JyK[end,end])*bk1[Int(K)+1]
        bk1[Int(K)]   -= JyK[Int(K),end]/(JxK[Int(K),Int(K)]*JyK[end,end])*bk1[Int(K)+1]
        bk1[Int(K)+1] /= JyK[Int(K)+1,end]

        resize!(Abk2x,Int(K))
        Abk2x[:]=bk1[1:Int(K)]
        resize!(Abk2y,Int(K))
        Abk2y[1:Int(K)-1]=Z
        Abk2y[end]=bk1[Int(K)+1]

        Abk1x,Abk2x=Abk2x,Abk1x
        Abk1y,Abk2y=Abk2y,Abk1y


        bk1,bk2 = bk2,bk1
        resize!(bk1,Int(K))
        bk1[:]=map((opx,opy)->x*opx+y*opy,Abk1x,Abk1y)
        bk1[:]-=Matrix(Bx)*Abk1x+Matrix(By)*Abk1y
        bk1[:]-=Matrix(Cx)*Abk2x+Matrix(Cy)*Abk2y
        for k=1:length(bk1)
            bk1[k]+=cfs[Int(K)][k]*I
        end
    end


    K =Block(1)
    Bx,By=view(Jx,K,K),view(Jy,K,K)
    Cx,Cy=view(Jx,K,K+1),view(Jy,K,K+1)
    JxK=view(Jx,K+1,K)
    JyK=view(Jy,K+1,K)

    bk1[1] /= JxK[1,1]
    bk1[1]   -= JyK[1,end]/(JxK[1,1]*JyK[2,end])*bk1[2]
    bk1[2] /= JyK[2,end]

    Abk1x,Abk2x=bk1[1:1],Abk1x
    Abk1y,Abk2y=[bk1[2]],Abk1y
    cfs[1][1]*I + x*Abk1x[1] + y*Abk1y[1] -
        Bx[1,1]*Abk1x[1] - By[1,1]*Abk1y[1] -
        (Matrix(Cx)*Abk2x)[1] - (Matrix(Cy)*Abk2y)[1]
end


function Multiplication(f::Fun{KoornwinderTriangle},S::KoornwinderTriangle)
    S1=space(f)
    op=operator_clenshaw2D(Lowering{1}(S1)→S1,Lowering{2}(S1)→S1,plan_evaluate(f).coefficients,Lowering{1}(S)→S,Lowering{2}(S)→S)
    MultiplicationWrapper(f,op)
end
