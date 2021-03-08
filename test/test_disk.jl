using MultivariateOrthogonalPolynomials, ClassicalOrthogonalPolynomials, StaticArrays, BlockArrays, BandedMatrices, FastTransforms, LinearAlgebra, Test
import MultivariateOrthogonalPolynomials: DiskTrav, grid, ZernikeConversion
import ClassicalOrthogonalPolynomials: HalfWeighted


@testset "Disk" begin
    @testset "Basics" begin
        @test ZernikeWeight(1)[SVector(0.1,0.2)] ≈ (1 - 0.1^2 - 0.2^2)
        @test ZernikeWeight(1) == ZernikeWeight(1)

        @test Zernike() == Zernike()
        @test Zernike(1) ≠ Zernike()
    end

    @testset "Evaluation" begin
        r,θ = 0.1, 0.2
        rθ = RadialCoordinate(r,θ)
        xy = SVector(rθ)
        @test Zernike()[rθ,1] ≈ Zernike()[xy,1] ≈ inv(sqrt(π)) ≈ zernikez(0, 0, rθ)
        @test Zernike()[rθ,Block(1)] ≈ Zernike()[xy,Block(1)] ≈ [inv(sqrt(π))]
        @test Zernike()[rθ,Block(2)] ≈ [2r/sqrt(π)*sin(θ), 2r/sqrt(π)*cos(θ)] ≈ [zernikez(1, -1, rθ), zernikez(1, 1, rθ)]
        @test Zernike()[rθ,Block(3)] ≈ [sqrt(3/π)*(2r^2-1),sqrt(6/π)*r^2*sin(2θ),sqrt(6/π)*r^2*cos(2θ)] ≈ [zernikez(2, 0, rθ), zernikez(2, -2, rθ), zernikez(2, 2, rθ)]
        @test Zernike()[rθ,Block(4)] ≈ [zernikez(3, -1, rθ), zernikez(3, 1, rθ), zernikez(3, -3, rθ), zernikez(3, 3, rθ)]

        @test zerniker(5, 0, norm(xy)) ≈ zernikez(5, 0, xy)
    end

    @testset "DiskTrav" begin
        @test DiskTrav(reshape([1],1,1)) == [1]
        @test DiskTrav([1 2 3]) == 1:3
        @test DiskTrav([1 2 3 5 6;
                        4 0 0 0 0]) == 1:6
        @test DiskTrav([1 2 3 5 6 9 10;
                        4 7 8 0 0 0  0]) == 1:10

        @test DiskTrav([1 2 3 5 6 9 10; 4 7 8 0 0 0  0])[Block(3)] == 4:6

        @test_throws ArgumentError DiskTrav([1 2])
        @test_throws ArgumentError DiskTrav([1 2 3 4])
        @test_throws ArgumentError DiskTrav([1 2 3; 4 5 6])
        @test_throws ArgumentError DiskTrav([1 2 3 4; 5 6 7 8])
    end

    @testset "Transform" begin
        for (a,b) in ((0,0), (0.1, 0.2), (0,1))
            Zn = Zernike(a,b)[:,Block.(Base.OneTo(3))]
            for k = 1:6
                @test factorize(Zn) \ Zernike(a,b)[:,k] ≈ [zeros(k-1); 1; zeros(6-k)]
            end

            Z = Zernike(a,b);
            xy = axes(Z,1); x,y = first.(xy),last.(xy);
            u = Z * (Z \ exp.(x .* cos.(y)))
            @test u[SVector(0.1,0.2)] ≈ exp(0.1cos(0.2))
        end
    end

    @testset "Laplacian" begin
        # u = r^m*f(r^2) * cos(m*θ)
        # u_r = (m*r^(m-1)*f(r^2) + 2r^(m+1)*f'(r^2)) * cos(m*θ)
        # u_rr = (m*(m-1)*r^(m-2)*f(r^2) + (4m+2)*r^m*f'(r^2) + 2r^(m+1)*f''(r^2)) * cos(m*θ)
        # u_rr + u_r/r + u_θθ/r^2 = (4*(m+1)*f'(r^2) + 2r*f''(r^2)) * r^m * cos(m*θ)
        # t = r^2, dt = 2r * dr, 4*(m+1)*f'(t) + 2sqrt(t)*f''(t) = 4 t^(-m) * d/dt * t^(m+1) f'(t)
        # d/ds * (1-s) * P_n^(1,m)(s) = -n*P_n^(0,m+1)(s)
        # use L^6 and L^6'
        # 2t-1 = s, 2dt = ds


        ℓ, m, b = 6, 2, 1
        x,y = 0.1,0.2
        r = sqrt(x^2+y^2)
        θ = atan(y,x)
        t = r^2
        u = xy -> zernikez(ℓ, m, b, xy)
        ur = r -> zerniker(ℓ, m, b, r)

        f = t -> sqrt(2^(m+b+2-iszero(m))/π) * normalizedjacobip((ℓ-m) ÷ 2, b, m, 2t-1)
        ur = r -> r^m*f(r^2)
        @test ur(r) ≈ zerniker(ℓ, m, b, r)
        @test f(r^2) ≈ r^(-m) * zerniker(ℓ, m, b, r)
        # u = xy -> ((x,y) = xy; ur(norm(xy)) * cos(m*atan(y,x)))
        # t = r^2; 4*(m+1)*derivative(f,t) + 4t*derivative2(f,t)
        
        # @test derivative(ur,r) ≈  m*r^(m-1)*f(r^2) + 2r^(m+1)*derivative(f,r^2)
        # @test derivative2(ur,r) ≈ m*(m-1)*r^(m-2)*f(r^2) + (4m+2)*r^m * derivative(f,r^2) + 4r^(m+2)*derivative2(f,r^2)
        # @test lapr(ur, m, r) ≈ 4*((m+1) * derivative(f,r^2) + r^2*derivative2(f,r^2)) * r^m
        # @test lapr(ur, m, r) ≈ 4*((m+1) * derivative(f,t) + t*derivative2(f,t)) * t^(m/2)
        

        ℓ, m, b = 1, 1, 1

        f = t -> sqrt(2^(m+b+2-iszero(m))/π) * (1-t) * normalizedjacobip((ℓ-m) ÷ 2, b, m, 2t-1)
        ur = r -> r^m*f(r^2)
        @test ur(r) ≈ (1-r^2) * zerniker(ℓ, m, b, r)

        D = Derivative(axes(Chebyshev(),1))
        D1 = Normalized(Jacobi(0, m+1)) \ (D * (HalfWeighted{:a}(Normalized(Jacobi(1, m)))))
        D2 = HalfWeighted{:b}(Normalized(Jacobi(1, m))) \ (D * (HalfWeighted{:b}(Normalized(Jacobi(0, m+1)))))

        @test (D1 * D2)[band(0)][1:10] ≈ -((1:∞) .* ((1+m):∞))[1:10]

                
        ℓ = m = 0; b= 1
        d = -4*((1:∞) .* ((m+1):∞))
        xy = SVector(0.1,0.2)
        # ℓ = m = 0; b= 1
        # u = xy -> (1 - norm(xy)^2) * zernikez(0, 0, 1, xy)
        # @test lap(u, xy...) ≈ Zernike(1)[xy,1] * (-4)

        # u = xy -> (1 - norm(xy)^2) * zernikez(1 , -1, 1, xy)
        # @test lap(u, xy...) ≈ Zernike(1)[xy,2] * (-4) * 1 * 2
        # u = xy -> (1 - norm(xy)^2) * zernikez(1 , 1, 1, xy)
        # @test lap(u, xy...) ≈ Zernike(1)[xy,3] * (-4) * 1 * 2

        # u = xy -> (1 - norm(xy)^2) * zernikez(2 , 0, 1, xy) # eval at 2
        # @test lap(u, xy...) ≈ Zernike(1)[xy,4] * (-4) * 2^2
        # u = xy -> (1 - norm(xy)^2) * zernikez(2 , -2, 1, xy) # eval at 1
        # @test lap(u, xy...) ≈ Zernike(1)[xy,5] * (-4) * 3
        # u = xy -> (1 - norm(xy)^2) * zernikez(2 , 2, 1, xy) # eval at 1
        # @test lap(u, xy...) ≈ Zernike(1)[xy,6] * (-4) * 3

        # u = xy -> (1 - norm(xy)^2) * zernikez(3 , -1, 1, xy) # eval at 2
        # @test lap(u, xy...) ≈ Zernike(1)[xy,7] * (-4) * 2 * 3
        # u = xy -> (1 - norm(xy)^2) * zernikez(3 , 1, 1, xy)
        # @test lap(u, xy...) ≈ Zernike(1)[xy,8] * (-4) * 2 * 3
        # u = xy -> (1 - norm(xy)^2) * zernikez(3 , -3, 1, xy) # eval at 1
        # @test lap(u, xy...) ≈ Zernike(1)[xy,9] * (-4) * 4 * 1
        # u = xy -> (1 - norm(xy)^2) * zernikez(3 , 3, 1, xy) # eval at 1
        # @test lap(u, xy...) ≈ Zernike(1)[xy,10] * (-4) * 4 * 1

        # u = xy -> (1 - norm(xy)^2) * zernikez(4 , 0, 1, xy) # eval at 3
        # @test lap(u, xy...) ≈ Zernike(1)[xy,11] * (-4) * 3^2
        # u = xy -> (1 - norm(xy)^2) * zernikez(4 , -2, 1, xy) # eval at 2
        # @test lap(u, xy...) ≈ Zernike(1)[xy,12] * (-4) * 4 * 2
        # u = xy -> (1 - norm(xy)^2) * zernikez(4 , 2, 1, xy) # eval at 2
        # @test lap(u, xy...) ≈ Zernike(1)[xy,13] * (-4) * 4 * 2
        # u = xy -> (1 - norm(xy)^2) * zernikez(4 , -4, 1, xy) # eval at 1
        # @test lap(u, xy...) ≈ Zernike(1)[xy,14] * (-4) * 5 * 1
        # u = xy -> (1 - norm(xy)^2) * zernikez(4 , 4, 1, xy) # eval at 1
        # @test lap(u, xy...) ≈ Zernike(1)[xy,15] * (-4) * 5 * 1

        WZ = Weighted(Zernike(1)) # Zernike(1) weighted by (1-r^2)
        Δ = Laplacian(axes(WZ,1))
        Δ_Z = Zernike(1) \ (Δ * WZ)

        xy = axes(WZ,1)
        x,y = first.(xy),last.(xy)
        u = @. (1 - x^2 - y^2) * exp(x*cos(y))
        Δu = @. (-exp(x*cos(y)) * (4 - x*(-5 + x^2 + y^2)cos(y) + (-1 + x^2 + y^2)cos(y)^2 - 4x*y*sin(y) + x^2*(x^2 + y^2-1)*sin(y)^2))
        @test (WZ * (WZ \ u))[SVector(0.1,0.2)] ≈ u[SVector(0.1,0.2)]
        @test (Δ_Z * (WZ \ u))[1:100]  ≈ (Zernike(1) \ Δu)[1:100] 
    end

    @testset "Conversion" begin
        R0 = Normalized(Jacobi(1, 0)) \ Normalized(Jacobi(0, 0))
        R1 = Normalized(Jacobi(1, 1)) \ Normalized(Jacobi(0, 1))
        R2 = Normalized(Jacobi(1, 2)) \ Normalized(Jacobi(0, 2))
        R3 = Normalized(Jacobi(1, 3)) \ Normalized(Jacobi(0, 3))

        xy = SVector(0.1,0.2)
        @test Zernike()[xy,Block(1)[1]] ≈ Zernike(1)[xy,Block(1)[1]]/sqrt(2)

        @test Zernike()[xy,Block(2)[1]] ≈ Zernike(1)[xy,Block(2)[1]]*R1[1,1]/sqrt(2)
        @test Zernike()[xy,Block(2)[2]] ≈ Zernike(1)[xy,Block(2)[2]]*R1[1,1]/sqrt(2)

        @test Zernike()[xy,Block(3)[1]] ≈ R0[1:2,2]'*Zernike(1)[xy,getindex.(Block.(1:2:3),1)]/sqrt(2)
        @test Zernike()[xy,Block(3)[2]] ≈ R2[1,1]*Zernike(1)[xy,Block(3)[2]]/sqrt(2)
        @test Zernike()[xy,Block(3)[3]] ≈ R2[1,1]*Zernike(1)[xy,Block(3)[3]]/sqrt(2)

        @test Zernike()[xy,Block(4)[1]] ≈ R1[1:2,2]'*Zernike(1)[xy,getindex.(Block.(2:2:4),1)]/sqrt(2)
        @test Zernike()[xy,Block(4)[2]] ≈ R1[1:2,2]'*Zernike(1)[xy,getindex.(Block.(2:2:4),2)]/sqrt(2)
        @test Zernike()[xy,Block(4)[3]] ≈ R3[1,1]*Zernike(1)[xy,Block(4)[3]]/sqrt(2)
        @test Zernike()[xy,Block(4)[4]] ≈ R3[1,1]*Zernike(1)[xy,Block(4)[4]]/sqrt(2)

        @test Zernike()[xy,Block(5)[1]] ≈ R0[2:3,3]'*Zernike(1)[xy,getindex.(Block.(3:2:5),1)]/sqrt(2)


        R = Zernike(1) \ Zernike()
        @test Zernike()[xy,Block.(1:6)]' ≈ Zernike(1)[xy,Block.(1:6)]'*R[Block.(1:6),Block.(1:6)] 
    end

    @testset "Lowering" begin
        L0 = Normalized(Jacobi(0, 0)) \ HalfWeighted{:a}(Normalized(Jacobi(1, 0)))
        L1 = Normalized(Jacobi(0, 1)) \ HalfWeighted{:a}(Normalized(Jacobi(1, 1)))
        L2 = Normalized(Jacobi(0, 2)) \ HalfWeighted{:a}(Normalized(Jacobi(1, 2)))
        L3 = Normalized(Jacobi(0, 3)) \ HalfWeighted{:a}(Normalized(Jacobi(1, 3)))

        xy = SVector(0.1,0.2)
        r = norm(xy)
        w = 1 - r^2
        x,y = xy
        θ = atan(y,x)

        sqrt(convert(T,2)^(m+a+b+2-iszero(m))/π) * r^m * normalizedjacobip((ℓ-m) ÷ 2, b, m+a, 2r^2-1)

        T = Float64
        @test sqrt(convert(T,2)^(2)/π) * (1 - (2r^2-1)) * normalizedjacobip(0, 1, 0, 2r^2-1) ≈ sqrt(convert(T,2)^(2)/π) * L0[1:2,1]'*normalizedjacobip.(0:1, 0, 0, 2r^2-1)
        @test sqrt(convert(T,2)^(2)/π) * (1 - (2r^2-1)) * normalizedjacobip(0, 1, 0, 2r^2-1) ≈ L0[1:2,1]'*zerniker.(0:2:2, 0, r) * sqrt(2)
        @test 2*sqrt(convert(T,2)^2/π) * (1- r^2) * normalizedjacobip(0, 1, 0, 2r^2-1) ≈ L0[1:2,1]'*zerniker.(0:2:2, 0, r) * sqrt(2)

        @test Zernike(1)[xy,Block(2)[1]] ≈ zerniker(1,1,1,r) * sin(θ) ≈ sqrt(convert(T,2)^(4)/π)* r * normalizedjacobip(0, 1, 1, 2r^2-1) * sin(θ)
        @test 2 * w * sqrt(convert(T,2)^(4)/π) *  normalizedjacobip(0, 1, 1, 2r^2-1) ≈ sqrt(convert(T,2)^(4)/π) * L1[1:2,1]'*normalizedjacobip.(0:1, 0, 1, 2r^2-1)
        @test 2 * w * sqrt(convert(T,2)^(4)/π) * r * normalizedjacobip(0, 1, 1, 2r^2-1) ≈ sqrt(convert(T,2)^(4)/π) * L1[1:2,1]'* r * normalizedjacobip.(0:1, 0, 1, 2r^2-1)
        @test 2 * w * zerniker(1,1,1,r) ≈ L1[1:2,1]'* zerniker.(1:2:3,1,r)*sqrt(2)
        @test 2 * w * zerniker(1,1,1,r)sin(θ) ≈ L1[1:2,1]'* zerniker.(1:2:3,1,r)sin(θ)*sqrt(2)
        

        @test w*Zernike(1)[xy,Block(1)[1]] ≈ L0[1:2,1]'*Zernike()[xy,getindex.(Block.(1:2:3),1)] / sqrt(2)

        @test w*Zernike(1)[xy,Block(2)[1]] ≈ L1[1:2,1]'*Zernike()[xy,getindex.(Block.(2:2:4),1)]/sqrt(2)
        @test w*Zernike(1)[xy,Block(2)[2]] ≈ L1[1:2,1]'*Zernike()[xy,getindex.(Block.(2:2:4),2)]/sqrt(2)

        @test w*Zernike(1)[xy,Block(3)[1]] ≈ L0[2:3,2]'*Zernike()[xy,getindex.(Block.(3:2:5),1)]/sqrt(2)
        @test w*Zernike(1)[xy,Block(3)[2]] ≈ L2[1:2,1]'*Zernike()[xy,getindex.(Block.(3:2:5),2)]/sqrt(2)
        @test w*Zernike(1)[xy,Block(3)[3]] ≈ L2[1:2,1]'*Zernike()[xy,getindex.(Block.(3:2:5),3)]/sqrt(2)

        L = Zernike() \ Weighted(Zernike(1))
        @test w*Zernike(1)[xy,Block.(1:5)]' ≈ Zernike()[xy,Block.(1:7)]'*L[Block.(1:7),Block.(1:5)] 
    end
end
