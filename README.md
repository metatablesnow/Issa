<div align="center">
<img src="./gh-assets/issa.svg" width="75%">
<br>
<br>
A runtime type validator with pretty errors and real types
<br>
<br>

[Github](https://github.com/metatablesnow/Issa) · [Wally Page](https://wally.run/package/metatablesnow/issa) · [Pesde Page](https://pesde.dev/packages/metatablesnow/issa)
</div>

---

<br>

>[!IMPORTANT]
>Issa is in beta, expect bugs and API changes!

### Features
- Types from runtime checks
- Pretty yet precise errors
- Small, composable predicates

### Installation

#### Wally
Add Issa to your `wally.toml` dependencies list:
```toml
[dependencies]
Is = "metatablesnow/issa@0.2.0"
```

#### Pesde
Add Issa to your `pesde.toml` dependencies list:
```toml
[dependencies]
Is = { name = "metatablesnow/issa", version = "0.2.0" }
```

#### Manual
Copy and paste the [source code](https://github.com/metatablesnow/Issa/blob/main/src/init.luau) into a module script.

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
type Age = typeof(IsAge.Type)

local bobsAge: Age = "Oops!" -- This will warn you!
```
use them to build more complex predicates:
```lua
local IsAnimal = Is.Interface({
    Name = Is.String(),
    Age = IsAge
}) 
```

or even refine them:

```lua
local IsAdult = Is.Refine(IsAnimal, function(self, animal)
    -- Refinements run last, so no need to check if this is a table!
    if animal.Age < 18 then
        return Is.Fail(animal, "number over 18", "animals age is under 18", animal, "Age", "field")
    end

    return Is.Pass()
end)

IsAdult(13) -- This will error!
```