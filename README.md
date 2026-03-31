<div align="center">
<img src="./gh-assets/issa.svg" width="50%">
<br>
<br>
	A runtime type validator with pretty errors and real types
</div>

---

### Features
- Types from runtime checks
- Pretty yet precise errors
- Small, composable predicates

### Guide

Every function in `Is` returns a `Predicate`.

```lua
local Is = require(path.to.Issa)

IsAge = Is.Number()
```

You can call a predicate:

```lua
local age = IsAge(18) -- This will pass, and return the input (18)
IsAge("Oops!") -- This will error
```

`Try` a predicate:
```lua
local success, data = IsAge:Try("Oops!")
-- success is false, and data is the error message

local success, data = IsAge:Try(18)
-- success is true, and data is the input (18)
```
`Type` a predicate:
```lua
type Age = typeof(IsAge:Type())

local bobsAge: Age = "Oops!" -- This will warn you!
```
use them to build more complex predicates:
```lua
-- Predicates are chainable!
local IsAgeOrName = IsAge:Or(Is.String())

local IsAnimal = Is.Interface({
    Name = Is.Number()
    Age = IsAge
}) 
```

or even refine them:

```lua
local IsAdult = IsAge:Refine(function(fail, pass, age)
    if age < 18 then
        return fail("age is below 18")
    end

    return pass()
end)

IsAdult(13) -- This will error!
```