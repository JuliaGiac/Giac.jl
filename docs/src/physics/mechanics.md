# Classical Mechanics

Giac.jl enables symbolic solutions to classical mechanics problems, including kinematics, dynamics, oscillations, and energy conservation.

## Setup

```julia
using Giac
using Giac.Commands: diff, integrate, solve, desolve

@giac_var t x v a m F g
```

## Kinematics

### Position, Velocity, and Acceleration

The fundamental relationships between position, velocity, and acceleration can be computed symbolically using differentiation and integration.

**Velocity from Position:**

```julia
@giac_var t

# Position function: x(t) = t²
x_t = t^2

# Velocity is the derivative of position
v_t = diff(x_t, t)
# Output: 2*t

# Acceleration is the derivative of velocity
a_t = diff(v_t, t)
# Output: 2
```

**Position from Acceleration:**

```julia
@giac_var t

# Constant acceleration (create as GiacExpr)
a_t = 2 + 0*t

# Integrate to get velocity
v_t = integrate(a_t, t)
# Output: 2*t (plus constant of integration)

# Integrate again to get position
x_t = integrate(2*t, t)
# Output: t^2
```

### Projectile Motion

Model projectile motion with initial velocity and gravitational acceleration:

```julia
@giac_var t g v0 theta

# Horizontal motion: x(t) = v0*cos(theta)*t
x_t = v0 * cos(theta) * t

# Vertical motion: y(t) = v0*sin(theta)*t - g*t²/2
y_t = v0 * sin(theta) * t - g * t^2 / 2

# Vertical velocity
vy_t = diff(y_t, t)
# Output: v0*sin(theta) - g*t

# Time of flight (when y = 0, t > 0)
solve(y_t ~ 0, t)
# Gives t = 0 and t = 2*v0*sin(theta)/g
```

### Uniformly Accelerated Motion

```julia
@giac_var v0 a t s

# SUVAT equations can be derived symbolically
# v = v0 + at
# s = v0*t + (1/2)*a*t²
# v² = v0² + 2*a*s

# Example: Find displacement given v0, a, t
s_expr = v0 * t + a * t^2 / 2
expand(s_expr)
```

## Dynamics

### Newton's Second Law

Solve force equations symbolically:

```julia
@giac_var F m a

# Newton's second law: F = ma
# Solve for acceleration
solve(F ~ m * a, a)
# Output: [F/m]

# Solve for mass
solve(F ~ m * a, m)
# Output: [F/a]
```

### Inclined Plane Problems

```julia
@giac_var m g theta a mu N

# Forces on an inclined plane
# Normal force: N = mg*cos(theta)
# Friction: f = mu*N

# Net force down the plane (no friction)
F_net = m * g * sin(theta)

# Acceleration down the plane
a_down = diff(F_net / m, theta) * 0 + g * sin(theta)
```

### Atwood Machine

```julia
@giac_var m1 m2 g a T

# Two masses connected by a rope over a pulley
# Equations: m1*g - T = m1*a  and  T - m2*g = m2*a

result = solve([m1*g - T ~ m1*a, T - m2*g ~ m2*a], [a, T])
# Solves for acceleration and tension
```

## Simple Harmonic Motion

### Differential Equation Approach

Solve the SHM differential equation using the D operator:

```julia
@giac_var t x(t) omega

# SHM equation: x'' + ω²x = 0 using D operator
ode = Differential(t, 2)(x) + omega^2 * x ~ 0
desolve([ode], t, :x)
# Output: Contains sin(omega*t) and cos(omega*t) terms
```

### Spring-Mass System

```julia
@giac_var k m omega x t

# For a spring-mass system: ω = sqrt(k/m)
# Period: T = 2π/ω = 2π*sqrt(m/k)

# Solve for angular frequency
solve(omega^2 ~ k/m, omega)
# Output: [sqrt(k/m), -sqrt(k/m)]
```

### Pendulum (Small Angle Approximation)

```julia
@giac_var t L g theta(t)

# For small angles: θ'' + (g/L)θ = 0
# Angular frequency: ω = sqrt(g/L)

ode = Differential(t, 2)(theta) + (g/L) * theta ~ 0
desolve([ode], t, :theta)
```

## Energy Conservation

### Kinetic and Potential Energy

Solve energy conservation problems:

```julia
@giac_var m v h g

# Conservation of energy: KE = PE
# (1/2)mv² = mgh

# Solve for velocity at height h
solve(m * v^2 / 2 ~ m * g * h, v)
# Output: [sqrt(2*g*h), -sqrt(2*g*h)]
```

### Work-Energy Theorem

```julia
@giac_var F d v1 v2 m

# Work done = Change in kinetic energy
# W = F*d = (1/2)mv2² - (1/2)mv1²

solve(F * d ~ m * v2^2 / 2 - m * v1^2 / 2, F)
# Solves for force given displacement and velocities
```

## Uniform Circular Motion

### Angular and Linear Velocity

```julia
@giac_var v r omega T

# Linear velocity: v = ω*r
solve(v ~ omega * r, omega)
# Output: [v/r]

# Period: T = 2π/ω (use invoke_cmd(:pi) for pi)
solve(T ~ 2*invoke_cmd(:pi) / omega, omega)
```

### Centripetal Acceleration

```julia
@giac_var v r a_c

# Centripetal acceleration: a_c = v²/r = ω²r
solve(a_c ~ v^2 / r, v)
# Output: [sqrt(a_c*r), -sqrt(a_c*r)]
```

## Table of Useful Commands

| Command | Physics Application |
|---------|---------------------|
| `diff(x, t)` | Velocity from position, acceleration from velocity |
| `integrate(a, t)` | Position from velocity, velocity from acceleration |
| `solve(F ~ m*a, a)` | Solve algebraic equations |
| `desolve(eq, y(t))` | Solve differential equations (SHM, oscillations) |

## Notes

- All quantities remain symbolic unless specific values are substituted
- Use `subst` to substitute numerical values for evaluation
- The D operator can be used for differential equations (see Differential Equations documentation)
- For numerical simulation, convert symbolic results to Julia functions using `to_julia`
