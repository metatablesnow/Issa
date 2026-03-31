--!strict
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

--selene: allow(undefined_variable)
type function getType(a)
	return a:readproperty(types.singleton("Type")):returns().head[1]
end

--selene: allow(undefined_variable)
type function IntersectionType(a, b, c, d, e, f)
	if f ~= nil then
		return types.intersectionof(a, b, c, d, e, f)
	elseif e ~= nil then
		return types.intersectionof(a, b, c, d, e)
	elseif d ~= nil then
		return types.intersectionof(a, b, c, d)
	elseif c ~= nil then
		return types.intersectionof(a, b, c)
	else
		return types.intersectionof(a, b)
	end
end

--selene: allow(undefined_variable)
type function Union(a, b, c, d, e, f)
	if f ~= nil then
		return types.unionof(a, b, c, d, e, f)
	elseif e ~= nil then
		return types.unionof(a, b, c, d, e)
	elseif d ~= nil then
		return types.unionof(a, b, c, d)
	elseif c ~= nil then
		return types.unionof(a, b, c)
	else
		return types.unionof(a, b)
	end
end

local INDENT = "    "

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
		return renderLeaf(displayInlineValue(value, 200), pathMatches(currentPath, err.path, false))
	end

	if typeof(value) == "table" 
	and pathMatches(currentPath, err.path, false) 
	and not expectedLooksTableLike(err.expected) 
	or (pathMatches(currentPath, err.path, false) and shouldCollapseWholeTable(err)) then
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
			highlightLine = if pathMatches(currentPath, err.path, false) then 1 else nil,
			highlightStart = if pathMatches(currentPath, err.path, false) then 1 else nil,
			highlightEnd = if pathMatches(currentPath, err.path, false) then 2 else nil,
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
		local shouldExpand = pathMatches(childPath, err.path, true) or pathMatches(err.path, childPath, true)

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
		table.insert(lines, INDENT.."...")
	end

	table.insert(lines, "}")

	if pathMatches(currentPath, err.path, false) and output.highlightLine == nil then
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
		errMessage = `{path}: expected {expected}, got {gotType} ({gotValue}): {err.message}`
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

local Is = {}
Is.__index = Is

type IsMethods<T> = {
	kind: string,
	_predicate: (self: Is<T>, input: unknown) -> Result,
	Refine: (
		self: Is<T>,
		refinement: (
			fail: (message: string) -> Result,
			pass: () -> Result,
			input: T
		) -> Result
	) -> Is<T>,
}

type IsMetatable<T> = {
	__index: IsMethods<T>,
	__call: (self: Is<T>, input: unknown) -> T,
}

export type Is<T> = typeof(setmetatable(
	{} :: IsMethods<T>,
	{} :: typeof(Is)
))

local function pass(): Result
	return { ok = true, error = {} }
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

function Is.new <T>(kind: string, check: (self: Is<T>, input: unknown) -> Result): Is<T>
	return setmetatable({
		kind = kind,
		_predicate = check,
}, Is) :: Is<T>
end

local function TypeOf(typeName: string): () -> Is<any>
	return function()
		return Is.new(typeName, function(self, input)
			if typeof(input) ~= typeName then
				return fail(self.kind, input)
			end

			return pass()
		end)
	end
end

function Is.__call<T>(self: Is<any>, input: T): T
	local result = (self :: any):_predicate(input) :: Result
	if result.ok then
		return input :: any
	end

	error(formatPrettyErr(input, result.error))
end

function Is.Try<T>(self: Is<T>, input: unknown): (boolean, T | string)
	local result = (self :: any):_predicate(input) :: Result
	if result.ok then
		return true, input :: any
	end

	return false, formatPrettyErr(input, result.error)
end

function Is.Type<T>(_self: Is<T>): T
	return (nil :: any) :: T
end

function Is.Refine<T>(
	predicate: Is<T>,
	refinement: (
		fail: (message: string) -> Result,
		pass: () -> Result,
		input: T
	) -> Result
): Is<T>
	local predicateCheck = predicate._predicate

	return Is.new(predicate.kind, function(self, input)
		local predicateCheckResult: Result = predicateCheck(self, input)

		if not predicateCheckResult.ok then
			return predicateCheckResult
		end

		local refinementFail = function(message: string): Result
			return fail(self.kind, input, message)
		end

		return refinement(refinementFail, pass, input :: T)
	end)
end
function Is.Predicate<T>(): Is<Is<T>>
	return Is.new("predicate", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return fail(self.kind, input)
		end

		if getmetatable(input) ~= Is then
			return fail(self.kind, input)
		end

		return pass()
	end) :: Is<Is<T>>
end

function Is.Any(): Is<any>
	return Is.new("any", function(): Result
		return pass()
	end) :: Is<any>
end

function Is.Literal<T>(value: T): Is<T>
	return Is.new("literal", function(self, input: unknown): Result
		if input ~= value then
			return fail(self.kind, input, `expected "{value}" got "{input}"`)
		end

		return pass()
	end)
end

Is.Exact = Is.Literal

function Is.Not<T>(predicate: Is<T>): Is<unknown>
	return Is.new("not", function(self, input: unknown): Result
		if predicate:_predicate(input).ok then
			return fail(self.kind, input, `expected not "{predicate.kind}" got "{input}"`)
		end

		return pass()
	end)
end

function Is.Optional<T>(predicate: Is<T>): Is<T?>
	return Is.new("optional", function(_self, input: unknown): Result
		if input == nil then
			return pass()
		end

		return (predicate :: any):_predicate(input)
	end)
end

--[[
	Primitive Types
]]
	
Is.Nil = TypeOf("nil") :: () -> Is<nil>
Is.Boolean = TypeOf("boolean") :: () -> Is<boolean>
Is.String = TypeOf("string") :: () -> Is<string>
Is.Thread = TypeOf("thread") :: () -> Is<thread>
Is.Function = TypeOf("function") :: () -> Is<(...any) -> (...any)>
Is.Table = TypeOf("table") :: () -> Is<{ [any]: any }>
Is.Buffer = TypeOf("buffer") :: () -> Is<buffer>
Is.Unknown = TypeOf("unknown") :: () -> Is<unknown>
Is.UserData = TypeOf("userdata") :: () -> Is<unknown>
Is.Number = TypeOf("number") :: () -> Is<number>

function Is.Never()
	return Is.new("never", function()
		error("value is never allowed")
	end)
end

--[[
	Structural / Complex Types
]]
	
function Is.Map<K, V>(expectedKey: Is<K>, expectedValue: Is<V>): Is<{ [K]: V }>
	return Is.new("list", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return fail(self.kind, input, "input is not a table")
		end

		local tbl = input :: { [any]: any }

		for key, value in tbl do
			local keyResult = expectedKey:_predicate(key)
			if not keyResult.ok then
				return failFromChild(keyResult.error, { kind = "key", key = key })
			end

			local valueResult = expectedValue:_predicate(value)
			if not valueResult.ok then
				return failFromChild(valueResult.error, { kind = "key", key = key })
			end
		end

		return pass()
	end) :: Is<{ [K]: V }>
end

function Is.Set<T>(key: Is<T>): Is<{ [T]: true }>
	return Is.Map(key, Is.Literal(true)) :: Is<{ [T]: true }>
end

function Is.Keys<T>(predicate: Is<T>): Is<{[T]: any}>
	return Is.Map(predicate, Is.Any())
end

function Is.Values<T>(predicate: Is<T>): Is<{[any]: T}>
	return Is.Map(Is.Any(), predicate)
end

function Is.Array<T>(predicate: Is<T>?): Is<{ [number]: T }>
	return Is.new("array", function(self, input: unknown): Result
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
				local result = (predicate :: Is<any>):_predicate(value)
				if not result.ok then
					return failFromChild(result.error, { kind = "index", key = key })
				end
			end
		end

		return pass()
	end) :: Is<{ [number]: T }>
end

--selene: allow(undefined_variable)
type function Interface(shape)
	local out = types.newtable()

	for key, prop in shape:properties() do
		out:setproperty(key, getType(prop.read))
	end

	return out
end

function Is.Interface<S, T>(shape: S): Is<Interface<S>>
	return Is.new("interface", function(self, input: unknown): Result
		if typeof(input) ~= "table" then
			return fail(self.kind, input, "input is not a table")
		end

		local tbl = input :: { [any]: any }

		for key, _ in tbl do
			if typeof(key) ~= "string" then
				return fail("string", key, "non-string key in interface", {
					{ kind = "key", key = key },
				})
			end
		end

		for key, predicate in (shape :: { [string]: Is<any>? }) do
			local result = (predicate :: Is<any>):_predicate(tbl[key])
			if not result.ok then
				return failFromChild(result.error, { kind = "field", key = key })
			end
		end

		return pass()
	end) :: Is<Interface<S>>
end

function Is.StrictInterface<S, T>(shape: S, strict: boolean?): Is<Interface<S> & {[never]: never}>
	return Is.new("interface", function(self, input: unknown): Result
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

		for key, predicate in (shape :: { [string]: Is<any>? }) do
			local result = (predicate :: Is<any>):_predicate(tbl[key])
			if not result.ok then
				return failFromChild(result.error, { kind = "field", key = key })
			end
		end

		return pass()
	end) :: Is<Interface<S>>
end

Is.Structure = Is.Interface
Is.StrictStructure = Is.StrictInterface

--[[
	Combination Types
]]

local intersection = function(...)
	local predicates: { Is<any> } = { ... }

	return Is.new("intersection", function(_self, input: unknown): Result
		for _, predicate in predicates do
			if predicate ~= nil then
				local result = predicate:_predicate(input)
				if not result.ok then
					return result
				end
			end
		end

		return pass()
	end) :: any
end

Is.Intersection = intersection :: <A, B, C, D, E, F>(
	a: Is<A>,
	b: Is<B>,
	c: Is<C>?,
	d: Is<D>?,
	e: Is<E>?,
	f: Is<F>?
) -> Is<IntersectionType<A, B, C, D, E, F>>

local union = (function(...)
	local predicates: { Is<any> } = { ... }

	return Is.new("union", function(self, input: unknown): Result
		for _, predicate in predicates do
			if predicate:_predicate(input).ok then
				return pass()
			end
		end

		return fail(self.kind, input, "input did not match any union member")
	end)
end) :: <A, B, C, D, E, F>(a: Is<A>, b: Is<B>, c: Is<C>?, d: Is<D>?, e: Is<E>?, f: Is<F>?) -> Is<Union<A, B, C, D, E, F>>

Is.Union = union
Is.Or = union

function Is.Instance(className: string?): Is<Instance>
	return Is.new(className and `Instance<{className}>` or "Instance", function(self, input: unknown): Result
		if typeof(input) ~= "Instance" then
			return fail(self.kind, input)
		end

		if className and not input:IsA(className) then
			return fail(self.kind, input, `expected IsA("{className}")`)
		end

		return pass()
	end) :: Is<Instance>
end

--[[
	Roblox Types
]]

Is.Axes = TypeOf("Axes") :: () -> Is<Axes>
Is.BrickColor = TypeOf("BrickColor") :: () -> Is<BrickColor>
Is.CatalogSearchParams = TypeOf("CatalogSearchParams") :: () -> Is<CatalogSearchParams>
Is.CFrame = TypeOf("CFrame") :: () -> Is<CFrame>
Is.Color3 = TypeOf("Color3") :: () -> Is<Color3>
Is.ColorSequence = TypeOf("ColorSequence") :: () -> Is<ColorSequence>
Is.ColorSequenceKeypoint = TypeOf("ColorSequenceKeypoint") :: () -> Is<ColorSequenceKeypoint>
Is.Content = TypeOf("Content") :: () -> Is<Content>
Is.DateTime = TypeOf("DateTime") :: () -> Is<DateTime>
Is.DockWidgetPluginGuiInfo = TypeOf("DockWidgetPluginGuiInfo") :: () -> Is<DockWidgetPluginGuiInfo>
Is.Enum = TypeOf("Enum") :: () -> Is<Enum>
Is.EnumItem = TypeOf("EnumItem") :: () -> Is<EnumItem>
Is.Faces = TypeOf("Faces") :: () -> Is<Faces>
Is.FloatCurveKey = TypeOf("FloatCurveKey") :: () -> Is<FloatCurveKey>
Is.Font = TypeOf("Font") :: () -> Is<Font>
Is.NumberRange = TypeOf("NumberRange") :: () -> Is<NumberRange>
Is.NumberSequence = TypeOf("NumberSequence") :: () -> Is<NumberSequence>
Is.NumberSequenceKeypoint = TypeOf("NumberSequenceKeypoint") :: () -> Is<NumberSequenceKeypoint>
Is.OverlapParams = TypeOf("OverlapParams") :: () -> Is<OverlapParams>
Is.Path2DControlPoint = TypeOf("Path2DControlPoint") :: () -> Is<Path2DControlPoint>
Is.PathWaypoint = TypeOf("PathWaypoint") :: () -> Is<PathWaypoint>
Is.PhysicalProperties = TypeOf("PhysicalProperties") :: () -> Is<PhysicalProperties>
Is.Random = TypeOf("Random") :: () -> Is<Random>
Is.Ray = TypeOf("Ray") :: () -> Is<Ray>
Is.RaycastParams = TypeOf("RaycastParams") :: () -> Is<RaycastParams>
Is.RaycastResult = TypeOf("RaycastResult") :: () -> Is<RaycastResult>
Is.RBXScriptConnection = TypeOf("RBXScriptConnection") :: () -> Is<RBXScriptConnection>
Is.RBXScriptSignal = TypeOf("RBXScriptSignal") :: () -> Is<RBXScriptSignal>
Is.Rect = TypeOf("Rect") :: () -> Is<Rect>
Is.Region3 = TypeOf("Region3") :: () -> Is<Region3>
Is.Region3int16 = TypeOf("Region3int16") :: () -> Is<Region3int16>
Is.RotationCurveKey = TypeOf("RotationCurveKey") :: () -> Is<RotationCurveKey>
Is.Secret = TypeOf("Secret") :: () -> Is<Secret>
Is.SecurityCapabilities = TypeOf("SecurityCapabilities") :: () -> Is<SecurityCapabilities>
Is.SharedTable = TypeOf("SharedTable") :: () -> Is<SharedTable>
Is.TweenInfo = TypeOf("TweenInfo") :: () -> Is<TweenInfo>
Is.UDim = TypeOf("UDim") :: () -> Is<UDim>
Is.UDim2 = TypeOf("UDim2") :: () -> Is<UDim2>
Is.ValueCurveKey = TypeOf("ValueCurveKey") :: () -> Is<ValueCurveKey>
Is.Vector2 = TypeOf("Vector2") :: () -> Is<Vector2>
Is.Vector2int16 = TypeOf("Vector2int16") :: () -> Is<Vector2int16>
Is.Vector3 = TypeOf("Vector3") :: () -> Is<Vector3>
Is.Vector3int16 = TypeOf("Vector3int16") :: () -> Is<Vector3int16>
Is.Vector3 = TypeOf("Vector3") :: () -> Is<Vector3>
Is.Vector3int16 = TypeOf("Vector3int16") :: () -> Is<Vector3int16>

return Is