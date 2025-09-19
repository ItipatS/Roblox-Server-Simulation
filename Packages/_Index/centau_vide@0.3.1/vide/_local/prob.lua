-- Let X ~ Geometric(p = 0.03). What is the value of Pr(X ≤ 30)?
-- Let f(x) = c x⁴ be a density function on [1, 3] where c is a normalising constant. Calculate Pr(X > 2.1).

type vec<T> = { T }

local function geometric(p: number, x: number): number
    return (1 - p)^(x - 1) * p
end

local function factorial(x: number): number
    local y = 1
    for i = 1, x do
        y *= i
    end
    return y
end

local function choose(n: number, r: number): number
    return factorial(n) / ( factorial(r) * factorial(n - r) )
end

local function mean(s: vec<number>): number
    local u = 0
    for _, x in s do
        u += x
    end
    return u / #s
end

local function variance(s: vec<number>): number
    local u = mean(s)
    local v = 0

    for i, x in s do
        v += (x - u)^2 
    end

    return v / (#s - 1)
end

local function binomial(n: number, p: number, x: number): number
    return choose(n, x) * p^x * (1 - p)^(n-x)
end

print(
    binomial(11, 0.06, 0) + binomial(11, 0.06, 1)
)

do
    local p = 0

    for i = 0, 9 do
        p += binomial(50, 0.08, i)
    end

    print(1 - p)
end

--Var[X] = E[X^2] - (E[X])^2
