--!strict

export type Error = {
	Input: unknown,
	Expected: string,
	Message: string?,
	Path: { [any]: any }?,
	Key: any?,
	BecauseOf: "key" | "field"?,
}

export type Result = { Ok: boolean, Error: Error }

--selene: allow(undefined_variable)
type function getType(a)
	return a:readproperty(types.singleton("Type"))
end

--selene: allow(undefined_variable)
export type function Map(key, value)
	local map = types.newtable()
	map:setindexer(getType(key), getType(value))

	return map
end

--selene: allow(undefined_variable)
export type function Intersection(a, b, c, d, e, f)
	if f.tag ~= "unknown" then
		return types.intersectionof(a, b, c, d, e, f)
	elseif e.tag ~= "unknown" then
		return types.intersectionof(a, b, c, d, e)
	elseif d.tag ~= "unknown" then
		return types.intersectionof(a, b, c, d)
	elseif c.tag ~= "unknown" then
		return types.intersectionof(a, b, c)
	else
		return types.intersectionof(getType(a), getType(b))
	end
end

--selene: allow(undefined_variable)
export type function Interface(shape)
	local out = types.newtable()

	for key, prop in shape:properties() do
		out:setproperty(key, getType(prop.read))
	end

	return out
end

local INDENT = "    "

local function formatKey(key: any): string
	if typeof(key) == "string" then
		return key
	elseif typeof(key) == "table" then
		return "{...}"
	elseif typeof(key) == "number" then
		return `[{tostring(key)}]`
	else
		return tostring(key)
	end
end

local function formatValue(value: any): string
	if typeof(value) == "string" then
		return `"{value}"`
	elseif typeof(value) == "table" then
		return "{...}"
	else
		return tostring(value)
	end
end

local function getIndent(depth): string
	return string.rep(INDENT, depth)
end

local function renderTable(
	input: { [any]: any },
	path: { [any]: any },
	key: any,
	depth: number,
	message: string,
	becauseOf: "key" | "field",
	lines: { string }?
): (boolean, { string })
	lines = lines or {}

	if input == path then
		local formattedKey = formatKey(key)
		local formattedValue = formatValue(input[key])

		table.insert(lines, getIndent(depth) .. "{")
		table.insert(lines, getIndent(depth + 1) .. formattedKey .. " = " .. formattedValue)
		if becauseOf == "field" then
			table.insert(
				lines,
				getIndent(depth + 1)
					.. string.rep(" ", #formattedKey + 3)
					.. string.rep("^", #formattedValue)
					.. " "
					.. message
			)
		else
			table.insert(lines, getIndent(depth + 1) .. string.rep("^", #formattedKey) .. " " .. message)
		end

		table.insert(lines, getIndent(depth) .. "}")
		return true, lines
	end

	for inputKey, inputValue in input do
		if typeof(inputValue) == "table" then
			local childLines = {}
			local found = renderTable(inputValue, path, key, depth + 1, message, becauseOf, childLines)

			if found then
				table.insert(lines, getIndent(depth) .. "{")
				table.insert(lines, getIndent(depth + 1) .. formatKey(inputKey) .. " = {")

				for i = 2, #childLines - 1 do
					table.insert(lines, childLines[i])
				end

				table.insert(lines, getIndent(depth + 1) .. "}")
				table.insert(lines, string.rep(INDENT, depth) .. "}")

				return true, lines
			end
		end
	end

	return false, lines
end

local function formatErr(err: Error): string
	local depth = 0
	local gotType = nil

	if err.Path and err.Key then
		if err.BecauseOf == "key" then
			gotType = typeof(err.Key)
		else
			gotType = typeof(err.Path[err.Key])
		end
	else
		gotType = typeof(err.Input)
	end

	local message = `expected {err.Expected}, got {gotType}`

	if err.Message then
		message ..= ": " .. err.Message
	end

	if typeof(err.Input) == "table" and typeof(err.Path) == "table" then
		local _, lines = renderTable(
			err.Input :: { [any]: any },
			err.Path :: { [any]: any },
			err.Key,
			depth,
			message,
			err.BecauseOf or "field"
		)

		return table.concat(lines, "\n")
	else
		local formattedValue = formatValue(err.Input)
		local lines = {}

		table.insert(lines, formattedValue)
		table.insert(lines, string.rep("^", #formattedValue) .. " " .. message)

		return table.concat(lines, "\n")
	end
end

local Predicate = {}

export type Predicate<T> = typeof(setmetatable(
	{} :: {
		Kind: string,
		Type: T,
		_predicate: (self: any, input: unknown) -> Result,
	},
	Predicate
))

function Predicate.new<T>(kind: string, check: (self: Predicate<T>, input: unknown) -> Result): Predicate<T>
	return setmetatable({
		Kind = kind,
		_predicate = check,
		Type = nil :: T,
	}, Predicate) :: Predicate<T>
end

function Predicate.__call<T>(self: Predicate<any>, input: T): T
	local result = self:_predicate(input)
	if result.Ok then
		return input
	end

	error(formatErr(result.Error))
end

function Predicate.Try<T>(self: Predicate<T>, input: unknown): (boolean, T | string)
	local result = self:_predicate(input)
	if result.Ok then
		return true, input
	end

	return false, formatErr(result.Error)
end

local Is = {}
Is.__index = Is

export type Is = typeof(setmetatable({}, Is))

function Is.Fail(
	input: any,
	expected: string,
	message: string?,
	path: {}?,
	key: string?,
	becauseOf: "field" | "key"?
): Result
	return {
		Ok = false,
		Error = {
			Input = input,
			Expected = expected,
			Message = message,
			Path = path :: { [any]: any },
			Key = key,
			BecauseOf = becauseOf,
		},
	}
end

function Is.Pass(): Result
	return { Ok = true, Error = {
		Expected = "",
	} }
end

local function TypeOf<T>(typeName: string): () -> Predicate<T>
	return function()
		return Predicate.new(typeName, function(self: Predicate<T>, input)
			if typeof(input) ~= typeName then
				return Is.Fail(input, self.Kind)
			end

			return Is.Pass()
		end)
	end
end

--[[
	Primitive Types
]]

Is.Nil = TypeOf("nil") :: () -> Predicate<nil>
Is.Boolean = TypeOf("boolean") :: () -> Predicate<boolean>
Is.String = TypeOf("string") :: () -> Predicate<string>
Is.Thread = TypeOf("thread") :: () -> Predicate<thread>
Is.Function = TypeOf("function") :: () -> Predicate<(...any) -> ...any>
Is.Table = TypeOf("table") :: () -> Predicate<{ [any]: any }>
Is.Buffer = TypeOf("buffer") :: () -> Predicate<buffer>
Is.Unknown = TypeOf("unknown") :: () -> Predicate<unknown>
Is.UserData = TypeOf("userdata") :: () -> Predicate<unknown>
Is.Number = TypeOf("number") :: () -> Predicate<number>

function Is.Any(): Predicate<any>
	return Predicate.new("any", function(): Result
		return Is.Pass()
	end)
end

function Is.Literal<T>(value: T): Predicate<T>
	return Predicate.new("literal", function(self, input: unknown): Result
		if input ~= value then
			return Is.Fail(input, self.Kind)
		end

		return Is.Pass()
	end)
end

Is.Exact = Is.Literal
Is.Singleton = Is.Literal

--[[
	Issa Types
]]

function Is.Predicate<T>(): Predicate<Predicate<T>>
	return Predicate.new("predicate", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return Is.Fail(input, self.Kind)
		end

		if getmetatable(input) ~= Is then
			return Is.Fail(input, self.Kind)
		end

		return Is.Pass()
	end) :: Predicate<Predicate<T>>
end

function Is.Not<T>(predicate: Predicate<T>): Predicate<unknown>
	return Predicate.new("not " .. predicate.Kind, function(self, input: unknown): Result
		if predicate:_predicate(input).Ok then
			return Is.Fail(input, self.Kind)
		end

		return Is.Pass()
	end)
end

function Is.Optional<T>(predicate: Predicate<T>): Predicate<T?>
	return Predicate.new("optional", function(_self, input: unknown): Result
		if input == nil then
			return Is.Pass()
		end

		return predicate:_predicate(input)
	end)
end

function Is.Never()
	return Predicate.new("never", function()
		error("value is never allowed")
	end)
end

--[[
	Structural / Complex Types
]]

function Is.Refine<T>(predicate: Predicate<T>, refinement: (input: T) -> Result): Predicate<T>
	local predicateCheck = predicate._predicate

	return Predicate.new(predicate.Kind, function(self, input)
		local predicateCheckResult = predicateCheck(self, input)

		if not predicateCheckResult.Ok then
			return predicateCheckResult
		end

		return refinement(input)
	end)
end

function Is.Map<K, V>(expectedKey: K & Predicate<any>, expectedValue: V & Predicate<any>): Predicate<Map<K, V>>
	return Predicate.new("list", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return Is.Fail(input, self.Kind)
		end

		local tbl = input :: { [any]: any }

		for key, value in tbl do
			local keyResult = expectedKey:_predicate(key)
			if not keyResult.Ok then
				local keyError = keyResult.Error
				return Is.Fail(input, keyError.Expected, keyError.Message, input, key, "key")
			end

			local valueResult = expectedValue:_predicate(value)
			if not valueResult.Ok then
				local valueError = valueResult.Error
				return Is.Fail(
					input,
					valueError.Expected,
					valueError.Message,
					valueError.Path or input,
					valueError.Key or key,
					valueError.BecauseOf
				)
			end
		end

		return Is.Pass()
	end) :: never
end

function Is.Set<T>(key: T & Predicate<any>): Predicate<Map<T, true>>
	return Is.Map(key, Is.Literal(true))
end

function Is.Keys<T>(predicate: T & Predicate<any>): Predicate<Map<Predicate<T>, any>>
	return Is.Map(predicate, Is.Any())
end

function Is.Values<T>(predicate: T & Predicate<any>): Predicate<Map<Predicate<any>, T>>
	return Is.Map(Is.Any(), predicate)
end

function Is.Array<T>(predicate: T & Predicate<any>): Predicate<Map<Predicate<number>, T>>
	return Predicate.new("array", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return Is.Fail(input, self.Kind)
		end

		local tbl = input :: { [any]: any }

		for key, value in tbl do
			if typeof(key) ~= "number" then
				return Is.Fail(input, "array key", "non-number key", tbl, key, "key")
			end

			if key % 1 ~= 0 or key < 1 then
				return Is.Fail(input, "array key", "non positive integer key", tbl, key, "key")
			end

			if predicate then
				local result = (predicate :: Predicate<any>):_predicate(value)
				if not result.Ok then
					return Is.Fail(
						input,
						result.Error.Expected,
						result.Error.Message,
						result.Error.Path,
						result.Error.Key,
						result.Error.BecauseOf
					)
				end
			end
		end

		return Is.Pass()
	end) :: Predicate<Map<number, T>>
end

function Is.Interface<S>(shape: S & { [string]: Predicate<any> }): Predicate<Interface<S>>
	return Predicate.new("interface", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return Is.Fail(input, self.Kind)
		end

		local tbl = input :: { [any]: any }

		for key, _ in tbl do
			if typeof(key) ~= "string" then
				return Is.Fail(input, self.Kind, "non-string key in interface", input, key, "key")
			end
		end

		for key, predicate in shape :: { [string]: Predicate<any>? } do
			if tbl[key] == nil then
				return Is.Fail(input, self.Kind, `missing key "{key}"`)
			end

			local result = (predicate :: Predicate<any>):_predicate(tbl[key])
			if not result.Ok then
				local err = result.Error

				return Is.Fail(
					input,
					err.Expected,
					err.Message,
					err.Path or tbl,
					err.Key or key,
					err.BecauseOf or "field"
				)
			end
		end

		return Is.Pass()
	end) :: Predicate<Interface<S>>
end

Is.Structure = Is.Interface

--[[
	Combination Types
]]

local function intersection(...)
	local predicates: { Predicate<any> } = { ... }

	local kinds = {}
	for _, predicate in predicates do
		table.insert(kinds, predicate.Kind)
	end

	local kind = table.concat(kinds, " & ")

	return Predicate.new(kind, function(_self, input: unknown): Result
		for _, predicate in predicates do
			if predicate ~= nil then
				local result = predicate:_predicate(input)
				if not result.Ok then
					result.Error.Expected = kind

					return result
				end
			end
		end

		return Is.Pass()
	end)
end

type IntersectionType = <A, B, C, D, E, F>(
	a: A,
	b: B,
	c: C?,
	d: D?,
	e: E?,
	f: F?
) -> Predicate<Intersection<A, B, C, D, E, F>>

Is.Intersection = intersection :: IntersectionType
Is.And = intersection :: IntersectionType

local union = function(...)
	local predicates: { Predicate<any> } = { ... }

	local kinds = {}
	for _, predicate in predicates do
		table.insert(kinds, predicate.Kind)
	end

	local kind = table.concat(kinds, " | ")

	return Predicate.new(kind, function(self, input: unknown): Result
		local err
		for _, predicate in predicates do
			local result = predicate:_predicate(input) :: Result
			if result.Ok then
				return Is.Pass()
			else
				err = result.Error
			end
		end

		if err then
			return Is.Fail(input, self.Kind, err.Message, err.Path, err.Key, err.BecauseOf)
		end

		return Is.Pass()
	end)
end

type UnionType =
	(<A, B>(a: Predicate<A>, b: Predicate<B>) -> Predicate<A | B>)
	& (<A, B, C>(a: Predicate<A>, b: Predicate<B>, c: Predicate<C>) -> Predicate<A | B | C>)
	& (<A, B, C, D>(a: Predicate<A>, b: Predicate<B>, c: Predicate<C>, d: Predicate<D>) -> Predicate<A | B | C | D>)
	& (<A, B, C, D, E>(
		a: Predicate<A>,
		b: Predicate<B>,
		c: Predicate<C>,
		d: Predicate<D>,
		e: Predicate<E>
	) -> Predicate<A | B | C | D | E>)
	& (<A, B, C, D, E, F>(
		a: Predicate<A>,
		b: Predicate<B>,
		c: Predicate<C>,
		d: Predicate<D>,
		e: Predicate<E>,
		f: Predicate<F>
	) -> Predicate<A | B | C | D | E | F>)

Is.Union = union :: UnionType
Is.Or = union :: UnionType

function Is.Instance(className: string?): Predicate<Instance>
	return Predicate.new(
			className and `Instance<{className}>` or "Instance",
			function(self, input: unknown): Result
				if typeof(input) ~= "Instance" then
					return Is.Fail(input, self.Kind)
				end

				if className and not input:IsA(className) then
					return Is.Fail(input, self.Kind, `expected IsA("{className}")`)
				end

				return Is.Pass()
			end
		) :: Predicate<Instance>
end

Is.IsA = Is.Instance

--[[
	Roblox Types
]]

Is.Axes = TypeOf("Axes") :: () -> Predicate<Axes>
Is.BrickColor = TypeOf("BrickColor") :: () -> Predicate<BrickColor>
Is.CatalogSearchParams = TypeOf("CatalogSearchParams") :: () -> Predicate<CatalogSearchParams>
Is.CFrame = TypeOf("CFrame") :: () -> Predicate<CFrame>
Is.Color3 = TypeOf("Color3") :: () -> Predicate<Color3>
Is.ColorSequence = TypeOf("ColorSequence") :: () -> Predicate<ColorSequence>
Is.ColorSequenceKeypoint = TypeOf("ColorSequenceKeypoint") :: () -> Predicate<ColorSequenceKeypoint>
Is.Content = TypeOf("Content") :: () -> Predicate<Content>
Is.DateTime = TypeOf("DateTime") :: () -> Predicate<DateTime>
Is.DockWidgetPluginGuiInfo = TypeOf("DockWidgetPluginGuiInfo") :: () -> Predicate<DockWidgetPluginGuiInfo>
Is.Enum = TypeOf("Enum") :: () -> Predicate<Enum>
Is.EnumItem = TypeOf("EnumItem") :: () -> Predicate<EnumItem>
Is.Faces = TypeOf("Faces") :: () -> Predicate<Faces>
Is.FloatCurveKey = TypeOf("FloatCurveKey") :: () -> Predicate<FloatCurveKey>
Is.Font = TypeOf("Font") :: () -> Predicate<Font>
Is.NumberRange = TypeOf("NumberRange") :: () -> Predicate<NumberRange>
Is.NumberSequence = TypeOf("NumberSequence") :: () -> Predicate<NumberSequence>
Is.NumberSequenceKeypoint = TypeOf("NumberSequenceKeypoint") :: () -> Predicate<NumberSequenceKeypoint>
Is.OverlapParams = TypeOf("OverlapParams") :: () -> Predicate<OverlapParams>
Is.Path2DControlPoint = TypeOf("Path2DControlPoint") :: () -> Predicate<Path2DControlPoint>
Is.PathWaypoint = TypeOf("PathWaypoint") :: () -> Predicate<PathWaypoint>
Is.PhysicalProperties = TypeOf("PhysicalProperties") :: () -> Predicate<PhysicalProperties>
Is.Random = TypeOf("Random") :: () -> Predicate<Random>
Is.Ray = TypeOf("Ray") :: () -> Predicate<Ray>
Is.RaycastParams = TypeOf("RaycastParams") :: () -> Predicate<RaycastParams>
Is.RaycastResult = TypeOf("RaycastResult") :: () -> Predicate<RaycastResult>
Is.RBXScriptConnection = TypeOf("RBXScriptConnection") :: () -> Predicate<RBXScriptConnection>
Is.RBXScriptSignal = TypeOf("RBXScriptSignal") :: () -> Predicate<RBXScriptSignal>
Is.Rect = TypeOf("Rect") :: () -> Predicate<Rect>
Is.Region3 = TypeOf("Region3") :: () -> Predicate<Region3>
Is.Region3int16 = TypeOf("Region3int16") :: () -> Predicate<Region3int16>
Is.RotationCurveKey = TypeOf("RotationCurveKey") :: () -> Predicate<RotationCurveKey>
Is.Secret = TypeOf("Secret") :: () -> Predicate<Secret>
Is.SecurityCapabilities = TypeOf("SecurityCapabilities") :: () -> Predicate<SecurityCapabilities>
Is.SharedTable = TypeOf("SharedTable") :: () -> Predicate<SharedTable>
Is.TweenInfo = TypeOf("TweenInfo") :: () -> Predicate<TweenInfo>
Is.UDim = TypeOf("UDim") :: () -> Predicate<UDim>
Is.UDim2 = TypeOf("UDim2") :: () -> Predicate<UDim2>
Is.ValueCurveKey = TypeOf("ValueCurveKey") :: () -> Predicate<ValueCurveKey>
Is.Vector2 = TypeOf("Vector2") :: () -> Predicate<Vector2>
Is.Vector2int16 = TypeOf("Vector2int16") :: () -> Predicate<Vector2int16>
Is.Vector3 = TypeOf("Vector3") :: () -> Predicate<Vector3>
Is.Vector3int16 = TypeOf("Vector3int16") :: () -> Predicate<Vector3int16>
Is.Vector3 = TypeOf("Vector3") :: () -> Predicate<Vector3>
Is.Vector3int16 = TypeOf("Vector3int16") :: () -> Predicate<Vector3int16>

return Is
