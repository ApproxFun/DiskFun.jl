abstract type AbstractModalInterlace{T} <: AbstractBandedBlockBandedMatrix{T} end

axes(Z::AbstractModalInterlace) = blockedrange.(oneto.(Z.MN))

"""
ModalInterlace
"""
struct ModalInterlace{T, MMNN<:Tuple} <: AbstractModalInterlace{T}
    ops
    MN::MMNN
    bandwidths::NTuple{2,Int}
end

ModalInterlace{T}(ops, MN::NTuple{2,Integer}, bandwidths::NTuple{2,Int}) where T = ModalInterlace{T,typeof(MN)}(ops, MN, bandwidths)
ModalInterlace(ops::AbstractVector{<:AbstractMatrix{T}}, MN::NTuple{2,Integer}, bandwidths::NTuple{2,Int}) where T = ModalInterlace{T}(ops, MN, bandwidths)



blockbandwidths(R::ModalInterlace) = R.bandwidths
subblockbandwidths(::ModalInterlace) = (0,0)


function Base.view(R::ModalInterlace{T}, KJ::Block{2}) where T
    K,J = KJ.n
    dat = Matrix{T}(undef,1,J)
    l,u = blockbandwidths(R)
    if iseven(J-K) && -l ≤ J - K ≤ u
        sh = (J-K)÷2
        if isodd(K)
            k = K÷2+1
            dat[1,1] = R.ops[1][k,k+sh]
        end
        for m in range(2-iseven(K); step=2, length=J÷2-max(0,sh))
            k = K÷2-m÷2+isodd(K)
            dat[1,m] = dat[1,m+1] = R.ops[m+1][k,k+sh]
        end
    else
        fill!(dat, zero(T))
    end
    _BandedMatrix(dat, K, 0, 0)
end

getindex(R::ModalInterlace, k::Integer, j::Integer) = R[findblockindex.(axes(R),(k,j))...]

struct ModalInterlaceLayout <: AbstractBandedBlockBandedLayout end
struct LazyModalInterlaceLayout <: AbstractLazyBandedBlockBandedLayout end

MemoryLayout(::Type{<:ModalInterlace}) = ModalInterlaceLayout()
MemoryLayout(::Type{<:ModalInterlace{<:Any,NTuple{2,InfiniteCardinal{0}}}}) = LazyModalInterlaceLayout()
sublayout(::Union{ModalInterlaceLayout,LazyModalInterlaceLayout}, ::Type{<:NTuple{2,BlockSlice{<:BlockOneTo}}}) = ModalInterlaceLayout()


function sub_materialize(::ModalInterlaceLayout, V::AbstractMatrix{T}) where T
    kr,jr = parentindices(V)
    KR,JR = kr.block,jr.block
    M,N = Int(last(KR)), Int(last(JR))
    R = parent(V)
    ModalInterlace{T}([R.ops[m][1:(M-m+2)÷2,1:(N-m+2)÷2] for m=1:min(N,M)], (M,N), R.bandwidths)
end

# act like lazy array
Base.BroadcastStyle(::Type{<:ModalInterlace{<:Any,NTuple{2,InfiniteCardinal{0}}}}) = LazyArrayStyle{2}()




"""
ShiftModalInterlace

for operators that shift the mode
"""
struct ShiftModalInterlace{T, MMNN<:Tuple} <: AbstractModalInterlace{T}
    ops
    MN::MMNN
    bandwidths::NTuple{2,Int}
    subbandwidth::Int
end

ShiftModalInterlace{T}(ops, MN::NTuple{2,Integer}, bandwidths::NTuple{2,Int}, subbandwidth::Int) where T = ShiftModalInterlace{T,typeof(MN)}(ops, MN, bandwidths, subbandwidth)
ShiftModalInterlace(ops::AbstractVector{<:AbstractMatrix{T}}, MN::NTuple{2,Integer}, bandwidths::NTuple{2,Int}, subbandwidth::Int) where T = ShiftModalInterlace{T}(ops, MN, bandwidths, subbandwidth)



blockbandwidths(R::ShiftModalInterlace) = R.bandwidths
subblockbandwidths(R::ShiftModalInterlace) = (-R.subbandwidth,R.subbandwidth)


function Base.view(R::ShiftModalInterlace{T}, KJ::Block{2}) where T
    K,J = KJ.n
    dat = Matrix{T}(undef,1,J)
    l,u = blockbandwidths(R)
    λ = R.subbandwidth
    if isodd(J-K) && -l ≤ J - K ≤ u
        sh = (J-K-1)÷2
        if iseven(K)
            k = K÷2+1
            dat[1,1] = R.ops[1][k,k+sh]
        end
        for m in range(2-iseven(K); step=2, length=J÷2-max(0,sh))
            k = K÷2-m÷2+isodd(K)
            dat[1,m] = dat[1,m+1] = R.ops[m+1][k,k+sh]
        end
    else
        fill!(dat, zero(T))
    end
    _BandedMatrix(dat, K, 0, 0)
end

getindex(R::ShiftModalInterlace, k::Integer, j::Integer) = R[findblockindex.(axes(R),(k,j))...]

struct ShiftModalInterlaceLayout <: AbstractBandedBlockBandedLayout end
struct LazyShiftModalInterlaceLayout <: AbstractLazyBandedBlockBandedLayout end

MemoryLayout(::Type{<:ShiftModalInterlace}) = ShiftModalInterlaceLayout()
MemoryLayout(::Type{<:ShiftModalInterlace{<:Any,NTuple{2,InfiniteCardinal{0}}}}) = LazyShiftModalInterlaceLayout()
sublayout(::Union{ShiftModalInterlaceLayout,LazyShiftModalInterlaceLayout}, ::Type{<:NTuple{2,BlockSlice{<:BlockOneTo}}}) = ShiftModalInterlaceLayout()


function sub_materialize(::ShiftModalInterlaceLayout, V::AbstractMatrix{T}) where T
    kr,jr = parentindices(V)
    KR,JR = kr.block,jr.block
    M,N = Int(last(KR)), Int(last(JR))
    R = parent(V)
    ShiftModalInterlace{T}([R.ops[m][1:(M-m+2)÷2,1:(N-m+2)÷2] for m=1:min(N,M)], (M,N), R.bandwidths)
end

# act like lazy array
Base.BroadcastStyle(::Type{<:ShiftModalInterlace{<:Any,NTuple{2,InfiniteCardinal{0}}}}) = LazyArrayStyle{2}()
