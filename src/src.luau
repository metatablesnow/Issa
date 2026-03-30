--!strict
local INDENT = "    "

export type Range = { number } | {min: number, max: number}

type PathSegment =
	{ kind: "field", key: string }
| { kind: "index", key: number }
| { kind: "key", key: unknown }

type ErrorInfo = {
	expected: string?,
	input: unknown?,
	message: string?,
	path: { PathSegment }?,
}

type Result = { ok: boolean, error: ErrorInfo }

type Rendered = {
	lines: { string },
	highlightLine: number?,
	highlightStart: number?,
	highlightEnd: number?,
}

export type Predicate<T> = typeof(setmetatable(
	{} :: {
		kind: string,
		_check: (self: any, input: unknown) -> Result,
		--Try: (self: Predicate<T>, input: unknown) -> (boolean, T | ErrorInfo),
		Type: (self: Predicate<T>) -> T,
	},
	{} :: {
		__call: (self: Predicate<T>, input: unknown) -> T,
	}
	))

local function pass(): Result
	return { ok = true, error = {} }
end

local function copyPath(path: { PathSegment }?, segment: PathSegment?, insertAtStart: boolean?): { PathSegment }
	local newPath = {}

	if path then
		for i = 1, #path do
			newPath[i] = path[i]
		end
	end

	if segment then
		if insertAtStart then
			table.insert(newPath, 1, segment)
		else
			table.insert(newPath, segment)
		end
	end

	return newPath
end

local function fail(expected: string, input: unknown, message: string?, path: { PathSegment }?): Result
	return {
		ok = false,
		error = {
			expected = expected or "valid value",
			input = input,
			message = message,
			path = copyPath(path),
		},
	}
end

local function failFromChild(err: ErrorInfo, segment: PathSegment): Result
	return {
		ok = false,
		error = {
			expected = err.expected,
			input = err.input,
			message = err.message,
			path = copyPath(err.path, segment, true),
		}
	}
end

local function inRange(range: Range, input: number): boolean
	local min = range[1] or (range :: never).min
	local max = range[2] or (range :: never).max

	if min and input < min then
		return false
	end
	if max and input > max then
		return false
	end
	return true
end

local function truncate(str: string, maxLen: number): string
	if #str <= maxLen then
		return str
	end

	return if maxLen <= 3 then str:sub(1, maxLen) else str:sub(1, maxLen - 3) .. "..."
end

local function displayInlineValue(input: unknown, maxLen: number?): string
	local limit = maxLen or 40
	local valueType = typeof(input)

	if valueType == "string" then
		return truncate(string.format("%q", input :: string), limit)
	elseif valueType == "Instance" then
		local instance = input :: Instance
		return truncate(`<{instance.ClassName} "{instance.Name}">`, limit)
	elseif valueType == "table" then
		return "{...}"
	elseif input == nil then
		return "nil"
	else
		return truncate(tostring(input), limit)
	end
end

local function pathMatches(a: { PathSegment }?, b: { PathSegment }?, prefix: boolean): boolean
	if a == nil and b == nil then
		return true
	end

	if a == nil then
		return prefix
	end

	if b == nil then
		return #a == 0
	end

	if (not prefix and #a ~= #b) or (prefix and #a > #b) then
		return false
	end

	for i = 1, #a do
		local A = a[i]
		local B = b[i]

		if A.kind ~= B.kind or A.key ~= B.key then
			return false
		end
	end

	return true
end

local function pathsEqual(a: { PathSegment }?, b: { PathSegment }?): boolean
	return pathMatches(a, b, false)
end

local function isPathPrefix(prefix: { PathSegment }?, full: { PathSegment }?): boolean
	return pathMatches(prefix, full, true)
end

local function renderLeaf(text: string, highlight: boolean): Rendered
	return {
		lines = { text },
		highlightLine = if highlight then 1 else nil,
		highlightStart = if highlight then 1 else nil,
		highlightEnd = if highlight then #text else nil,
	}
end

local function shiftRendered(rendered: Rendered, prefix: string): Rendered
	local newLines = table.clone(rendered.lines)
	newLines[1] = prefix .. newLines[1]

	local startCol = rendered.highlightStart
	local endCol = rendered.highlightEnd

	if rendered.highlightLine == 1 then
		if startCol then
			startCol += #prefix
		end
		if endCol then
			endCol += #prefix
		end
	end

	return {
		lines = newLines,
		highlightLine = rendered.highlightLine,
		highlightStart = startCol,
		highlightEnd = endCol,
	}
end

local function expectedLooksTableLike(expected: string?): boolean
	if not expected then
		return false
	end

	return expected == "table"
		or expected == "interface"
		or string.find(expected, "{", 1, true) ~= nil
		or string.find(expected, "table", 1, true) ~= nil
end

local function shouldCollapseWholeTable(err: ErrorInfo): boolean
	return typeof(err.input) == "table" and expectedLooksTableLike(err.expected)
end

local function renderValueDeep(
	value: unknown,
	err: ErrorInfo,
	currentPath: { PathSegment }?,
	depth: number
): Rendered
	if typeof(value) ~= "table" then
		return renderLeaf(displayInlineValue(value, 200), pathsEqual(currentPath, err.path))
	end

	if typeof(value) == "table" 
	and pathsEqual(currentPath, err.path) 
	and not expectedLooksTableLike(err.expected) 
	or (pathsEqual(currentPath, err.path) and shouldCollapseWholeTable(err)) then
		return renderLeaf("{...}", true)
	end

	local tbl = value :: { [any]: any }
	local keys = {}

	for key in tbl do
		table.insert(keys, key)
	end

	table.sort(keys :: {any}, function(a, b)
		local ta = typeof(a)
		local tb = typeof(b)

		if ta == tb then
			if ta == "number" or ta == "string" then
				return (a :: number) < (b :: number)
			end
			return tostring(a) < tostring(b)
		end

		if ta == "number" then
			return true
		end
		if tb == "number" then
			return false
		end
		if ta == "string" then
			return true
		end
		if tb == "string" then
			return false
		end

		return ta < tb
	end)

	if #keys == 0 then
		return {
			lines = { "{}" },
			highlightLine = if pathsEqual(currentPath, err.path) then 1 else nil,
			highlightStart = if pathsEqual(currentPath, err.path) then 1 else nil,
			highlightEnd = if pathsEqual(currentPath, err.path) then 2 else nil,
		}
	end

	local lines = { "{" }
	local output: Rendered = {
		lines = lines,
		highlightLine = nil,
		highlightStart = nil,
		highlightEnd = nil,
	}

	local hiddenCount = 0

	for _, key in keys do
		local childValue = tbl[key]
		local segment: PathSegment =
			if typeof(key) == "string" then
			{ kind = "field", key = key }
			elseif typeof(key) == "number" then
			{ kind = "index", key = key }
			else
			{ kind = "key", key = key }

		local childPath = copyPath(currentPath, segment)
		local shouldExpand = isPathPrefix(childPath, err.path) or isPathPrefix(err.path, childPath)

		if not shouldExpand then
			hiddenCount += 1
			continue
		end

		local keyText =
			if segment.kind == "field" and typeof(key) == "string" and string.match(key :: string, "^[%a_][%w_]*$") then
			(key :: string) .. " = "
			else
			"[" .. displayInlineValue(key, 60) .. "] = "

		local rendered = shiftRendered(renderValueDeep(childValue, err, childPath, depth + 1), keyText)
		local newLines = table.create(#rendered.lines)

		for i, line in rendered.lines do
			newLines[i] = INDENT .. line
		end

		local startCol = rendered.highlightStart
		local endCol = rendered.highlightEnd

		if rendered.highlightLine then
			if startCol then
				startCol += #INDENT
			end
			if endCol then
				endCol += #INDENT
			end
		end

		local childRendered = {
			lines = newLines :: { string },
			highlightLine = rendered.highlightLine,
			highlightStart = startCol,
			highlightEnd = endCol,
		}

		local startLine = #lines + 1
		for _, line in childRendered.lines do
			table.insert(lines :: {string | unknown}, line)
		end

		if childRendered.highlightLine then
			output.highlightLine = startLine + childRendered.highlightLine - 1
			output.highlightStart = childRendered.highlightStart
			output.highlightEnd = childRendered.highlightEnd
		end
	end

	if hiddenCount > 0 then
		table.insert(lines, "    ...")
	end

	table.insert(lines, "}")

	if pathsEqual(currentPath, err.path) and output.highlightLine == nil then
		output.highlightLine = 1
		output.highlightStart = 1
		output.highlightEnd = 1
	end

	return output
end

local function formatPrettyErr(rootInput: unknown, err: ErrorInfo): string
	local path = "input"

	for _, segment in err.path or {} do
		if segment.kind == "field" then
			path ..= "." .. segment.key
		else
			path ..= "[" .. tostring(segment.key) .. "]"
		end
	end

	local expected = err.expected or "valid value"
	local gotType = typeof(err.input)
	local gotValue = displayInlineValue(err.input, 120)

	local errMessage
	if err.message then
		errMessage =  `{path}: expected {expected}, got {gotType} ({gotValue})\n  ↳ {err.message}`
	else
		errMessage = `{path}: expected {expected}, got {gotType} ({gotValue})`
	end

	if typeof(rootInput) ~= "table" then
		return errMessage
	end

	if shouldCollapseWholeTable(err) and (not err.path or #err.path == 0) then
		local token = "{...}"
		return `{errMessage}\n\n{token}\n{string.rep("^", #token)}`
	end

	local rendered = renderValueDeep(rootInput, err, {}, 0)

	if not rendered.highlightLine or not rendered.highlightStart or not rendered.highlightEnd then
		return `{errMessage}\n\n{table.concat(rendered.lines, "\n")}`
	end

	local pointers = table.clone(rendered.lines)
	table.insert(
		pointers,
		rendered.highlightLine + 1,
		string.rep(" ", rendered.highlightStart - 1)
			.. string.rep("^", math.max(1, rendered.highlightEnd - rendered.highlightStart + 1)).." "..errMessage
	)

	return `\n\n{table.concat(pointers, "\n")}`
end

local Predicate = {}
Predicate.__index = Predicate

local function MakePredicate<T>(
	kind: string,
	check: (self: Predicate<T>, input: unknown) -> Result
): Predicate<T>
	return setmetatable({
		kind = kind,
		_check = check,
	}, Predicate) :: any
end

local function MakeTypeof(typeName: string): () -> Predicate<any>
	return function()
		return MakePredicate(typeName, function(self, input)
			if typeof(input) ~= typeName then
				return fail(self.kind, input)
			end

			return pass()
		end)
	end
end

function Predicate.__call<T>(self: Predicate<T>, input: unknown): T
	local result = (self :: any):_check(input) :: Result
	if result.ok then
		return input :: any
	end

	error(formatPrettyErr(input, result.error), 2)
end

function Predicate.Try<T>(self: Predicate<T>, input: unknown): (boolean, T | ErrorInfo)
	local result = (self :: any):_check(input) :: Result
	if result.ok then
		return true, input :: any
	end

	return false, result.error
end

function Predicate.Type<T>(_self: Predicate<T>): T
	return (nil :: any) :: T
end

local Is = {}
function Is.Predicate<T>(): Predicate<Predicate<T>>
	return MakePredicate("predicate", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return fail(self.kind, input)
		end

		if getmetatable(input) ~= Predicate then
			return fail(self.kind, input)
		end

		return pass()
	end) :: Predicate<Predicate<T>>
end

function Is.Any(): Predicate<any>
	return MakePredicate("any", function(): Result
		return pass()
	end) :: Predicate<any>
end

function Is.Literal<T>(value: T): Predicate<T>
	return MakePredicate("literal", function(self, input: unknown): Result
		if input ~= value then
			return fail(self.kind, input, `expected "{value}" got "{input}"`)
		end

		return pass()
	end)
end

Is.Exact = Is.Literal

function Is.Not<T>(predicate: Predicate<T>): Predicate<unknown>
	return MakePredicate("not", function(self, input: unknown): Result
		if predicate:_check(input).ok then
			return fail(self.kind, input, `expected not "{predicate.kind}" got "{input}"`)
		end

		return pass()
	end)
end

function Is.Optional<T>(predicate: Predicate<T>): Predicate<T?>
	return MakePredicate("optional", function(_self, input: unknown): Result
		if input == nil then
			return pass()
		end

		return (predicate :: any):_check(input)
	end)
end

--[[
	Primitive Types
]]
	
Is.Nil = MakeTypeof("nil") :: () -> Predicate<nil>
Is.Boolean = MakeTypeof("boolean") :: () -> Predicate<boolean>
Is.String = MakeTypeof("string") :: () -> Predicate<string>
Is.Thread = MakeTypeof("thread") :: () -> Predicate<thread>
Is.Function = MakeTypeof("function") :: () -> Predicate<(...any) -> (...any)>
Is.Table = MakeTypeof("table") :: () -> Predicate<{ [any]: any }>
Is.Buffer = MakeTypeof("buffer") :: () -> Predicate<buffer>
Is.Unknown = MakeTypeof("unknown") :: () -> Predicate<unknown>

function Is.Never()
	return MakePredicate("never", function()
		error("value is never allowed")
	end)
end

function Is.Number(limits: {
	range: Range?,
	integer: boolean?,
}?): Predicate<number>
	return MakePredicate("number", function(self, input: unknown): Result
		if typeof(input) ~= "number" then
			return fail(self.kind, input)
		end

		if limits and limits.integer and input % 1 ~= 0 then
			return fail(self.kind, input, "input is not an integer")
		end

		if limits and limits.range and not inRange(limits.range, input) then
			return fail(self.kind, input, "input outside of range")
		end

		return pass()
	end) :: Predicate<number>
end

--[[
	Structural / Complex Types
]]
	
function Is.Map<K, V>(expectedKey: Predicate<K>, expectedValue: Predicate<V>): Predicate<{ [K]: V }>
	return MakePredicate("list", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return fail(self.kind, input, "input is not a table")
		end

		local tbl = input :: { [any]: any }

		for key, value in tbl do
			local keyResult = expectedKey:_check(key)
			if not keyResult.ok then
				return failFromChild(keyResult.error, { kind = "key", key = key })
			end

			local valueResult = expectedValue:_check(value)
			if not valueResult.ok then
				return failFromChild(valueResult.error, { kind = "key", key = key })
			end
		end

		return pass()
	end) :: Predicate<{ [K]: V }>
end

function Is.Set<T>(key: Predicate<T>): Predicate<{[T]: true}>
	return Is.Map(key, Is.Literal(true)) :: Predicate<{[T]: true}>
end

function Is.Array<T>(predicate: Predicate<T>?): Predicate<{ [number]: T }>
	return MakePredicate("array", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return fail(self.kind, input, "input is not a table")
		end

		local tbl = input :: { [any]: any }

		for key, value in tbl do
			if typeof(key) ~= "number" then
				return fail("number", key, `non-number key "{tostring(key)}"`, {
					{ kind = "key", key = key },
				})
			end

			if key % 1 ~= 0 or key < 1 then
				return fail("positive integer index", key, `invalid array index "{key}"`, {
					{ kind = "key", key = key },
				})
			end

			if predicate then
				local result = (predicate :: Predicate<any>):_check(value)
				if not result.ok then
					return failFromChild(result.error, { kind = "index", key = key })
				end
			end
		end

		return pass()
	end) :: Predicate<{ [number]: T }>
end

--selene: allow(undefined_variable)
type function Interface(shape)
	local out = types.newtable()

	for key, prop in shape:properties() do
		out:setproperty(key, getType(prop.read))
	end

	return out
end

function Is.Interface<S>(shape: S, strict: boolean?): Predicate<Interface<S>>
	return MakePredicate("interface", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return fail(self.kind, input, "input is not a table")
		end

		local tbl = input :: { [any]: any }

		for key, value in tbl do
			if typeof(key) ~= "string" then
				return fail("string", key, "non-string key in interface", {
					{ kind = "key", key = key },
				})
			end

			if strict and (shape :: any)[key] == nil then
				return fail("never", value, `unexpected key "{key}"`, {
					{ kind = "field", key = key },
				})
			end
		end

		for key, predicate in (shape :: { [string]: Predicate<any>? }) do
			local result = (predicate :: Predicate<any>):_check(tbl[key])
			if not result.ok then
				return failFromChild(result.error, { kind = "field", key = key })
			end
		end

		return pass()
	end) :: Predicate<Interface<S>>
end

--[[
	Combination Types
]]

--selene: allow(undefined_variable)
type function getType(a)
	return a:readproperty(types.singleton("Type")):returns().head[1]
end

--selene: allow(undefined_variable)
type function Intersection(a, b, c, d, e, f)
	local aType = getType(a)
	local bType = getType(b)

	if f and f:is("table") then
		return types.intersectionof(aType, bType, getType(c), getType(d), getType(e), getType(f))
	elseif e and e:is("table") then
		return types.intersectionof(aType, bType, getType(c), getType(d), getType(e))
	elseif d and d:is("table") then
		return types.intersectionof(aType, bType, getType(c), getType(d))
	elseif c and c:is("table") then
		return types.intersectionof(aType, bType, getType(c))
	else
		return types.intersectionof(aType, bType)
	end
end

function Is.Intersection<A, B, C, D, E, F>(a: A, b: B, c: C?, d: D?, e: E?, f: F?): Predicate<Intersection<A, B, C, D, E, F>>
	local predicates = { a, b, c, d, e, f }

	return MakePredicate("intersection", function(_self, input: unknown): Result
		for _, predicate in predicates do
			local result = (predicate :: Predicate<A | B>):_check(input)
			if not result.ok then
				return result
			end
		end

		return pass()
	end) :: Predicate<Intersection<A, B, C, D, E, F>>
end

type UnionType =
	(<A, B>(a: Predicate<A>, b: Predicate<B>) -> Predicate<A | B>) &
	(<A, B, C>(a: Predicate<A>, b: Predicate<B>, c: Predicate<C>) -> Predicate<A | B | C>) &
	(<A, B, C, D>(a: Predicate<A>, b: Predicate<B>, c: Predicate<C>, d: Predicate<D>) -> Predicate<A | B | C | D>) &
	(<A, B, C, D, E>(a: Predicate<A>, b: Predicate<B>, c: Predicate<C>, d: Predicate<D>, e: Predicate<E>) -> Predicate<A | B | C | D | E>) &
	(<A, B, C, D, E, F>(a: Predicate<A>, b: Predicate<B>, c: Predicate<C>, d: Predicate<D>, e: Predicate<E>, f: Predicate<F>) -> Predicate<A | B | C | D | E | F>)

local union = (function(...)
	local predicates: { Predicate<any> } = { ... }

	return MakePredicate("union", function(self, input: unknown): Result
		for _, predicate in predicates do
			if predicate:_check(input).ok then
				return pass()
			end
		end

		return fail(self.kind, input, "input did not match any union member")
	end)
end) :: UnionType

Is.Union = union
Is.Or = union

function Is.Instance(className: string?): Predicate<Instance>
	return MakePredicate(className and `Instance<{className}>` or "Instance", function(self, input: unknown): Result
		if typeof(input) ~= "Instance" then
			return fail(self.kind, input)
		end

		if className and not input:IsA(className) then
			return fail(self.kind, input, `expected IsA("{className}")`)
		end

		return pass()
	end) :: Predicate<Instance>
end

--[[
	Roblox Types
]]

Is.Axes = MakeTypeof("Axes") :: () -> Predicate<Axes>
Is.BrickColor = MakeTypeof("BrickColor") :: () -> Predicate<BrickColor>
Is.CatalogSearchParams = MakeTypeof("CatalogSearchParams") :: () -> Predicate<CatalogSearchParams>
Is.CFrame = MakeTypeof("CFrame") :: () -> Predicate<CFrame>
Is.Color3 = MakeTypeof("Color3") :: () -> Predicate<Color3>
Is.ColorSequence = MakeTypeof("ColorSequence") :: () -> Predicate<ColorSequence>
Is.ColorSequenceKeypoint = MakeTypeof("ColorSequenceKeypoint") :: () -> Predicate<ColorSequenceKeypoint>
Is.Content = MakeTypeof("Content") :: () -> Predicate<Content>
Is.DateTime = MakeTypeof("DateTime") :: () -> Predicate<DateTime>
Is.DockWidgetPluginGuiInfo = MakeTypeof("DockWidgetPluginGuiInfo") :: () -> Predicate<DockWidgetPluginGuiInfo>
Is.Enum = MakeTypeof("Enum") :: () -> Predicate<Enum>
Is.EnumItem = MakeTypeof("EnumItem") :: () -> Predicate<EnumItem>
Is.Faces = MakeTypeof("Faces") :: () -> Predicate<Faces>
Is.FloatCurveKey = MakeTypeof("FloatCurveKey") :: () -> Predicate<FloatCurveKey>
Is.Font = MakeTypeof("Font") :: () -> Predicate<Font>
Is.NumberRange = MakeTypeof("NumberRange") :: () -> Predicate<NumberRange>
Is.NumberSequence = MakeTypeof("NumberSequence") :: () -> Predicate<NumberSequence>
Is.NumberSequenceKeypoint = MakeTypeof("NumberSequenceKeypoint") :: () -> Predicate<NumberSequenceKeypoint>
Is.OverlapParams = MakeTypeof("OverlapParams") :: () -> Predicate<OverlapParams>
Is.Path2DControlPoint = MakeTypeof("Path2DControlPoint") :: () -> Predicate<Path2DControlPoint>
Is.PathWaypoint = MakeTypeof("PathWaypoint") :: () -> Predicate<PathWaypoint>
Is.PhysicalProperties = MakeTypeof("PhysicalProperties") :: () -> Predicate<PhysicalProperties>
Is.Random = MakeTypeof("Random") :: () -> Predicate<Random>
Is.Ray = MakeTypeof("Ray") :: () -> Predicate<Ray>
Is.RaycastParams = MakeTypeof("RaycastParams") :: () -> Predicate<RaycastParams>
Is.RaycastResult = MakeTypeof("RaycastResult") :: () -> Predicate<RaycastResult>
Is.RBXScriptConnection = MakeTypeof("RBXScriptConnection") :: () -> Predicate<RBXScriptConnection>
Is.RBXScriptSignal = MakeTypeof("RBXScriptSignal") :: () -> Predicate<RBXScriptSignal>
Is.Rect = MakeTypeof("Rect") :: () -> Predicate<Rect>
Is.Region3 = MakeTypeof("Region3") :: () -> Predicate<Region3>
Is.Region3int16 = MakeTypeof("Region3int16") :: () -> Predicate<Region3int16>
Is.RotationCurveKey = MakeTypeof("RotationCurveKey") :: () -> Predicate<RotationCurveKey>
Is.Secret = MakeTypeof("Secret") :: () -> Predicate<Secret>
Is.SecurityCapabilities = MakeTypeof("SecurityCapabilities") :: () -> Predicate<SecurityCapabilities>
Is.SharedTable = MakeTypeof("SharedTable") :: () -> Predicate<SharedTable>
Is.TweenInfo = MakeTypeof("TweenInfo") :: () -> Predicate<TweenInfo>
Is.UDim = MakeTypeof("UDim") :: () -> Predicate<UDim>
Is.UDim2 = MakeTypeof("UDim2") :: () -> Predicate<UDim2>
Is.ValueCurveKey = MakeTypeof("ValueCurveKey") :: () -> Predicate<ValueCurveKey>
Is.Vector2 = MakeTypeof("Vector2") :: () -> Predicate<Vector2>
Is.Vector2int16 = MakeTypeof("Vector2int16") :: () -> Predicate<Vector2int16>
Is.Vector3 = MakeTypeof("Vector3") :: () -> Predicate<Vector3>
Is.Vector3int16 = MakeTypeof("Vector3int16") :: () -> Predicate<Vector3int16>

return Is