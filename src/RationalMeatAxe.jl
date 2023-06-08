module RationalMeatAxe

using Hecke

using Hecke: ModAlgHom
import Base: reshape
import Hecke: sub, domain, codomain, mat

include("RandomAlgebras.jl")

__init__() = Hecke.add_verbosity_scope(:rma)

Mod = Hecke.ModAlgAss
AlgElem = Hecke.AlgAssElem{QQFieldElem, AlgAss{QQFieldElem}}

# TODO: Hecke.decompose anschauen, oder gleich ganz Hecke.AlgAss

@doc raw"""
    meataxe(M::Mod) -> Vector{Mod}

Given a semisimple module $M$ return simple submodules which add up to $M$.

The underlying algebra $A$ can be chosen as a subalgebra of $\operator{Mat}_N\mathbf Q$.
Implements algorithm by Allan Steel.
"""
function meataxe(M::Mod)
    reduce(vcat, split_homogeneous.(homogeneous_components(M)))
end

@doc raw"""
    homogeneous_components(M::Mod) -> Vector{Mod}

Return homogeneous $S_i$ such that $M=\bigoplus_i S_i=M$.

The input $M$ needs to be semisimple. Homogeneous means to be isomorphic to a
direct sum of copies of some simple module.

See also [`split_homogeneous(::Mod)`](@ref).
"""
function homogeneous_components(M::Mod) :: Vector{Mod}
    @vprint :rma "# Homogeneous Components of $M\n"
    B = basis_of_center_of_endomorphism_ring(M)
    B === nothing && return [M]
    dim_of_center = length(B)
    QQx, x = polynomial_ring(QQ, :x)
    @vprint :rma "## Iterating through basis $B of the center of the endomorphism ring\n"
    for b in B
        @vprint :rma "Current basis element is\n"
        @v_do :rma display(b)
        f = minpoly(b)
        is_irreducible(f) && degree(f) == dim_of_center && return [M]
        fs = factor(f)
        length(fs) == 1 && continue
        p, e = first(fs)
        f1 = p^e
        f2 = divexact(f, f1)
        @vprint :rma "Minimal polynomial is $f with coprime factors $f1 and $f2\n"
        f1, f2 = QQx(f1), QQx(f2)
        _1, s, t = gcdx(f1, f2)
        f1, f2 = s*f1, t*f2
        @vprint :rma "Using multiples $f1 and $f2 summing up to 1\n"
        @assert _1 == 1
        ss1 = homogeneous_components(M, f1(QQMatrix(b)))
        ss2 = homogeneous_components(M, f2(QQMatrix(b)))
        return [ss1; ss2]
    end
    return [M]
end

function homogeneous_components(M::Mod, A::QQMatrix) :: Vector{Mod}
    @vprint :rma "### Splitting at\n"
    @v_do :rma display(A)
    MA = sub(M, A)
    Hecke.pushindent()
    L = homogeneous_components(MA)
    Hecke.popindent()
    return L
end

basis_of_center_of_endomorphism_ring(M::Mod) = lll_saturate(center_of_endomorphism_ring(M))

function center_of_endomorphism_ring(M::Mod)
    endM, endMhom = Hecke.endomorphism_algebra(M)
    z, zhom = center(endM)
    return numerator.(matrix.(endMhom.(zhom.(basis(z)))))
end

Mat = Union{ZZMatrix, QQMatrix}

Hecke.lll(a::Vector{ZZMatrix}) = isempty(a) ? a : frommatrix(lll(asmatrix(a)), size(a[1])...)
lll_saturate(a::Vector{ZZMatrix}) = isempty(a) ? a : frommatrix(lll(saturate(asmatrix(a))), size(a[1])...)
lll_saturate(a::Vector{QQMatrix}) = QQMatrix.(lll_saturate(numerator.(a)))
lll_saturate(v::Vector{T}) where T<:NCRingElem = isempty(v) ? v : parent(v[1]).(lll_saturate(matrix.(v))) :: Vector{T}


asmatrix(v::Vector{T}) where T <: MatElem = reduce(vcat, newshape.(v, 1, :)) :: T

frommatrix(a::T, r::Int, c::Int) where T <: MatElem = T[newshape(x, r, c) for x in eachrow(a)]

newshape(a::MatElem, dims::Union{Int, Colon}...) = newshape(a, dims)
newshape(a::MatElem, dims::NTuple{2, Union{Int, Colon}}) = newshape(a, Base._reshape_uncolon(a, dims))

# Iterate column wise, probably somewhat inefficient, as flint stores matrices rowwise.
function newshape(a::T, dims::NTuple{2, Int}) ::T where T<:MatElem
    b = similar(a, dims...)
    for (I, x) in zip(CartesianIndices(dims), a)
        b[I] = x
    end
    return b
end

Base.eachrow(a::MatElem) = (view(a, i, :) for i in axes(a, 1))
Base.eachcol(a::MatElem) = (view(a, :, i) for i in axes(a, 2))

numerator(a::QQMatrix) = MatrixSpace(ZZ, size(a)...)(ZZ.(denominator(a)*a)) :: ZZMatrix

raw"""
    ModHom(M::Hecke.ModAlgAss, A::Mat)

Module automorphism from $M$ to $M⋅T$, where $AT=H$ is the HNF of $A$.
"""
struct ModHom
    rank :: Int
    T :: Mat
    invT :: Mat
    domain :: Hecke.ModAlgAss
    # Sei 𝓐 ⊆ K^{𝑚×𝑚} K-rechts-Algebra, jedes X∈𝓐 also auf dem Modul $M=K^𝑚$
    # von rechts operierende Matrix.
    # Ferner sei A∈End_K(𝓐), also AX=XA und H=AT die Spalten-HNF von A mit 𝑛 nicht-null-Spalten.
    # Vermittels des Isomorphismus M⋅A → M⋅H=M⋅AT, m ↦ mT operiert X auf m∈M⋅H als mT⁻¹XT.
    # Nun hat HT⁻¹XT = AXT = XAT = XH ebenfalls nur n nicht-null-Spalten, ist also von der Form
    # (m×n)   0.
    function ModHom(domain::Hecke.ModAlgAss, A::Mat)
        H, T = hnf_with_transform(transpose(A))
        T = transpose!(T)
        return new(Hecke.rank_of_ref(H), T, inv(T), domain)
    end
end
domain(a::ModHom) = a.domain
codomain(a::ModHom) = image(a, a.domain)
mat(a::ModHom) = a.T
image(h::ModHom, x::Mat) = submatrix(h.invT * x * h.T, h.rank)
image(h::ModHom, M::Mod) = Amodule(image.((h,), Hecke.action_of_gens(M)))

struct SubMod
    M :: Hecke.ModAlgAss
    hom :: ModHom
    SubMod(h::ModHom) = new(codomain(h), h)
end
SubMod(M::Hecke.ModAlgAss, A::Mat) = SubMod(ModHom(M, A))
sub(M::Hecke.ModAlgAss, A::Mat) = codomain(ModHom(M, A))

ModHom(a::Hecke.ModAlgHom) = ModHom(domain(a), matrix(a))
sub(a::Hecke.ModAlgHom) = codomain(ModHom(a))


# TᵀAᵀ = Hᵀ ⇔ (AT)ᵀ = Hᵀ ⇔ AT = H
column_hnf_with_transform(A) = transpose.(hnf_with_transform(transpose(A)))

submatrix(A::QQMatrix, n::Int) = (@assert A[1:n, n+1:end] == 0; A[1:n, 1:n])


function embedmatrix(A::QQMatrix, m::Int)
    B = zero(MatrixSpace(QQ, m, m))
    n = size(A, 1)
    B[1:n, 1:n] = A
    B
end

# ===

@doc raw"""
    split_homogeneous(M::Mod) -> Vector{Mod}

Return pairwise isomorphic simple $S_i$ such that $M=\bigoplus_i S_i=M$.

The input $M$ needs to be homogeneous, i.e. allow such a decomposition.

See also [`homogeneous_components(::Mod)`](@ref).
"""
function split_homogeneous(M::Mod)
    endM, endM_to_actual_endM = Hecke.endomorphism_algebra(M)
    endMAA, endMAA_to_endM = AlgAss(endM)
    A, h = Hecke._as_algebra_over_center(endMAA)
    si = schur_index(A)
    d = dim(A)
    m = divexact(sqrt(d), si)
    m == 1 && return [M]
    s = maximal_order_basis_search(endM)
    fs = factor(minpoly(s))
    @assert length(fs) > 1
    singularElements = (endM_to_actual_endM((p^e)(s)) for (p, e) in fs)
    return reduce(vcat, split_homogeneous.(sub.(singularElements)))
end

Hecke.kernel(a::Hecke.ModAlgHom) = sub(domain(a), kernel(matrix(a))[2])

maximal_order_basis_search(A::Hecke.AbsAlgAss) = maximal_order_basis_search(maximal_order(A))
maximal_order_basis_search(o::Hecke.AlgAssAbsOrd) = maximal_order_basis_search(o.basis_alg)

function maximal_order_basis_search(v::Vector)
    (a = find(is_split, v)) !== nothing && return a
    for b1 in v, b2 in v
        is_split(b1 * b2) && return b1 * b2
        is_split(b1 + b2) && return b1 + b2
    end
    while a === nothing
        a = find(is_split, lll_saturate([x * rand(v) for x in v]))
    end
    return a
end

find(f, v) = (i = findfirst(f, v); i === nothing ? nothing : v[i])

is_split(a) = length(factor(minpoly(a))) > 1

end
