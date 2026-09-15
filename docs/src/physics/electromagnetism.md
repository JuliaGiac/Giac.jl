# Electromagnetism

Giac.jl enables symbolic solutions to electromagnetism problems, including electrostatics, circuit analysis, and electromagnetic waves.

## Setup

```julia
using Giac
using Giac.Commands: diff, integrate, solve, desolve

@giac_var q r t V I R C L k
```

## Electrostatics

### Coulomb's Law

Calculate electric forces between point charges:

```julia
@giac_var q1 q2 r k F

# Coulomb's law: F = k*q1*q2/r²
# Solve for distance given force
solve(F ~ k * q1 * q2 / r^2, r)
# Returns r in terms of other variables

# Solve for charge
solve(F ~ k * q1 * q2 / r^2, q1)
# Output: [F*r^2/(k*q2)]
```

### Electric Field

```julia
@giac_var q r k E

# Electric field: E = k*q/r²
# Solve for charge given field
solve(E ~ k * q / r^2, q)
# Output: [E*r^2/k]
```

### Electric Potential

```julia
@giac_var q r k V

# Electric potential: V = k*q/r
# Solve for charge
solve(V ~ k * q / r, q) |> first |> simplify
# Output: [V*r/k]

# Relationship between field and potential
# E = -dV/dr
V_r = k * q / r
E_r = -diff(V_r, r)
# Output: k*q/r^2
```

### Capacitor Systems

```julia
@giac_var C1 C2 C_eq

# Series capacitors: 1/C_eq = 1/C1 + 1/C2
solve(1/C_eq ~ 1/C1 + 1/C2, C_eq)

# Parallel capacitors: C_eq = C1 + C2
C_parallel = C1 + C2
```

## Circuit Analysis

### Ohm's Law

```julia
@giac_var V I R

# Ohm's law: V = IR
solve(V ~ I * R, I)
# Output: [V/R]

solve(V ~ I * R, R)
# Output: [V/I]
```

### RC Circuits

Solve the RC circuit differential equation using the D operator:

```julia
@giac_var t R C V(t)

# Capacitor discharging: dV/dt + V/(RC) = 0 using D operator
ode = Differential(t)(V) + V/(R*C) ~ 0
desolve([ode], t, :V)
# Output: V(t) = c_0*exp(-t/(R*C))

# With initial condition, use function syntax from @giac_var V(t)
# The solution will contain exp(-t/(R*C)) terms
```

### Time Constant

```julia
@giac_var R C tau

# Time constant: τ = RC
solve(tau ~ R * C, R)
# Output: [tau/C]
```

### RL Circuits

Solve the RL circuit differential equation using the D operator:

```julia
@giac_var t R L I(t) E

# Current decay in RL circuit: dI/dt + (R/L)*I = 0 using D operator
ode = Differential(t)(I) + R/L*I ~ 0
initial = I(0) ~ E / R
desolve([ode, initial], t, :I)
# Output: I(t) = E/R*exp(-R*t/L)

# Time constant for RL circuit: τ = L/R
# Initial current: I0 = E/R
```

### RLC Circuits

```julia
@giac_var R L C omega

# RLC resonance frequency: ω = 1/sqrt(LC)
solve(omega^2 ~ 1/(L*C), omega)
# Output: [sqrt(1/(L*C)), -sqrt(1/(L*C))]
```

## Energy in Electromagnetic Systems

### Capacitor Energy

```julia
@giac_var C V E Q

# Energy stored in capacitor: E = (1/2)CV²
solve(E ~ C * V^2 / 2, V)
# Output: [sqrt(2*E/C), -sqrt(2*E/C)]

# Alternative form: E = Q²/(2C)
solve(E ~ Q^2 / (2 * C), Q)
```

### Inductor Energy

```julia
@giac_var L I E

# Energy stored in inductor: E = (1/2)LI²
solve(E ~ L * I^2 / 2, I)
# Output: [sqrt(2*E/L), -sqrt(2*E/L)]
```

### Power Dissipation

```julia
@giac_var P V I R

# Power: P = IV = I²R = V²/R
solve(P ~ I * V, I)
# Output: [P/V]

solve(P ~ I^2 * R, I)
# Output: [sqrt(P/R), -sqrt(P/R)]
```

## Electromagnetic Waves

### Wave Equation

```julia
@giac_var x t k omega E0

# Electric field wave: E = E0*sin(kx - ωt)
E = E0 * sin(k * x - omega * t)

# Time derivative
dE_dt = diff(E, t)
# Output: -E0*omega*cos(k*x-omega*t)

# Spatial derivative
dE_dx = diff(E, x)
# Output: E0*k*cos(k*x-omega*t)
```

### Dispersion Relation

```julia
@giac_var k omega c

# For electromagnetic waves in vacuum: ω = c*k
solve(omega ~ c * k, k)
# Output: [omega/c]
```

### Wavelength and Frequency

```julia
@giac_var lambda f c

# c = λf
solve(c ~ lambda * f, lambda)
# Output: [c/f]
```

## Table of Useful Equations

| Equation | Description |
|----------|-------------|
| `F = k*q1*q2/r²` | Coulomb's law |
| `V = k*q/r` | Electric potential |
| `V = IR` | Ohm's law |
| `τ = RC` | RC time constant |
| `τ = L/R` | RL time constant |
| `ω = 1/√(LC)` | RLC resonance |
| `E = (1/2)CV²` | Capacitor energy |
| `E = (1/2)LI²` | Inductor energy |

## Notes

- Use `desolve` for solving circuit differential equations
- The time constant τ appears in exponential decay solutions
- For AC circuits, complex impedance analysis can be performed symbolically
- Electromagnetic wave solutions involve sinusoidal functions
