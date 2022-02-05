local Environment = getgenv()._DrawingEnvironment

local UNDEFINED = "%%UNDEFINED%%"

local Error = {
	DestroyedSet = "The %s property of %s is locked because the object has been destroyed.",
	ReadOnlySet = "Property %s is read-only and cannot be set.",
	InvalidSet = "Invalid property %s (%s expected, got %s)",
	InvalidProperty = "%s is not a valid member of %s \"%s\"",
	InvalidValue = "Invalid value to property %s (%s expected, got %s)",
	CircularParentRef = "Attempt to set parent of %s to %s would result in a circular reference",
	UnknownProperty = "%s is not a valid member of %s \"%s\"",
}

local Signal = Environment.Signal

local DrawingElement do
	DrawingElement = {
		ClassProperties = {}
	}

	local function RecursiveFlatten(Flattened, Count, Children)
		for Child in next, Children do
			Count += 1
			Flattened[Count] = Child

			RecursiveFlatten(Flattened, Count, Child._Children)
		end

		return Flattened
	end

	local function DeepCopy(Value)
		if type(Value) ~= "table" then
			return Value
		end

		local Copy = {}
		for i, v in next, Value do
			Copy[DeepCopy(i)] = DeepCopy(v)
		end

		return Copy
	end

	local ElementClasses = {}
	local function IsElementObject(Object)
		return type(Object) == "table" and ElementClasses[Object.Class] == getrawmetatable(Object)
	end

	local Counter = 0
	local function IncrementCounter()
		Counter += 1
		return Counter
	end

	local ElementGui = {}
	ElementGui.Name = "ElementGui"

	-- GuiObject is an abstract class inherited by all DrawingElement objects.
	local GuiObject do
		GuiObject = {}
		GuiObject.__index = GuiObject

		local ClassPropertiesDraft = {
			Visible = false,
			ZIndex = 1,
			Transparency = 1,
			Color = Color3.new(0, 0, 0),
			Parent = UNDEFINED,
			AnchorPoint = Vector2.new(0, 0),
			Position = Vector2.new(0, 0),
			Name = "GuiObject",
			AbsolutePosition = Vector2.new(0, 0),
			Class = "GuiObject"
		}
		local ReadOnlyProps = {
			AbsolutePosition = true,
			Class = true,
		}
		DrawingElement.ClassProperties.GuiObject = ClassPropertiesDraft

		function GuiObject.new()
			local Object = setmetatable({
				_Connections = {},
				_DebugId = IncrementCounter(),
				_Destroyed = false,
				_FullName = "GuiObject",

				_Properties = DeepCopy(ClassPropertiesDraft)
			}, GuiObject)

			return Object
		end

		function GuiObject:__newindex(Key, Value)
			debug.profilebegin("GuiObject_newindex_" .. tostring(Key))

			if ReadOnlyProps[Key] then
				error(Error.ReadOnlySet:format(tostring(Key)))
			elseif Key == "Visible" then
				assert(type(Value) == "boolean", Error.InvalidValue:format(tostring(Key), "boolean", typeof(Value)))
				local Parent = self._Properties.Parent
				self:_UpdateVisible(Value, Parent ~= UNDEFINED and Parent._DrawingObject.Visible, Parent)
			elseif Key == "Parent" then
				self:_SetParent(Key, Value)
			elseif Key == "Name" then
				local Props = self._Properties
				Props.Name = Value
				self:_UpdateFullName(Props.Parent)
			elseif Key == "Color" then
				assert(typeof(Value) == "Color3", Error.InvalidValue:format(tostring(Key), "Color3", typeof(Value)))
				self._Properties.Color = Value
				self._DrawingObject.Color = Value
			elseif Key == "ZIndex" then
				self._Properties.ZIndex = Value
				self._DrawingObject.ZIndex = Value
			else
				error(Error.UnknownProperty:format(tostring(Key), self.Class, self._FullName))
			end

			debug.profileend()
		end
		function GuiObject:_SetParent(Key, Value)
			assert(Value == nil or IsElementObject(Value), Error.InvalidSet:format(tostring(Key), "ElementObject", tostring(Value)))
			debug.profilebegin("_SetParent_" .. self.Class)

			local DidUpdate = false
			if Value ~= nil then
				debug.profilebegin("Verify parent")
				if Value == self._Properties.Parent or Value == self then
					return nil, debug.profileend()
				end

				local NewParent = Value
				while NewParent ~= UNDEFINED do
					if NewParent == self then
						error(Error.CircularParentRef:format(self._FullName, Value._FullName))
						return nil, debug.profileend()
					end

					NewParent = NewParent._Properties.Parent
				end
				debug.profileend()

				debug.profilebegin("Update properties")
				DidUpdate = true

				Value._Children[self] = true
				debug.profileend()
			elseif self._Properties.Parent ~= UNDEFINED then
				debug.profilebegin("Update properties (2)")
				DidUpdate = true

				local CurrentParent = self._Properties.Parent
				CurrentParent._Children[self] = nil
				debug.profileend()
			end

			if DidUpdate then
				debug.profilebegin("Update data")
				self._Properties.Parent = Value
				self:_UpdateFullName(Value)
				self:_UpdatePosition()
				debug.profileend()
			end

			debug.profileend()
		end
		function GuiObject:_UpdateVisible(Value, ParentVisible, Parent)
			debug.profilebegin("namecall__UpdateVisible")
			self._Properties.Visible = Value

			local VisibleValue = Value
			if Parent ~= UNDEFINED then
				VisibleValue = ParentVisible and Value
			end
			self._DrawingObject.Visible = VisibleValue

			for Child in next, self._Children do
				Child:UpdateVisible(Value, VisibleValue, self)
			end
			debug.profileend()
		end
		function GuiObject:_UpdateFullName(ObjectParent)
			debug.profilebegin("namecall__UpdateFullName")
			local FullName = self._Destroyed and "" or "ElementGui."

			debug.profilebegin("Grab parents")
			local ParentNames = {}
			while ObjectParent ~= UNDEFINED do
				local ParentProps = ObjectParent._Properties
				table.insert(ParentNames, ParentProps.Name)
				ObjectParent = ParentProps.Parent
			end
			debug.profileend()

			debug.profilebegin("Reverse-iterate")
			for Idx = #ParentNames, 1, -1 do
				FullName = FullName .. ParentNames[Idx] .. "."
			end
			debug.profileend()

			self._FullName = FullName .. self._Properties.Name

			for Child in next, self._Children do
				Child:_UpdateFullName(self)
			end
			debug.profileend()
		end
		function GuiObject:_UpdatePosition(ParentPosition, RootPositionProp, PositionProps)
			debug.profilebegin("namecall__UpdatePosition")

			debug.profilebegin("Get properties")
			local Props = self._Properties

			local RelativePositions = {}
			local AbsolutePositions = {}

			local ParentAbsolutePosition = (ParentPosition or (Props.Parent ~= UNDEFINED and Props.Parent._Properties.AbsolutePosition) or Vector2.zero)
			local DidMove = false
			for PropName, PropValue in next, PositionProps do
				local RelativePosition = PropValue ~= UNDEFINED and PropValue or Props[PropName]
				RelativePositions[PropName] = RelativePosition
				AbsolutePositions[PropName] = ParentAbsolutePosition + RelativePosition

				if AbsolutePositions[PropName] ~= Props["Absolute" .. PropName] then
					DidMove = true
				end
			end
			debug.profileend()

			if DidMove then
				debug.profilebegin("Update drawing object")
				local DrawingObject = self._DrawingObject

				for PropName, PropValue in next, AbsolutePositions do
					DrawingObject[PropName] = PropValue
				end
				debug.profileend()

				debug.profilebegin("Update element properties")
				local ElementAbsolutePosition = AbsolutePositions[RootPositionProp]

				Props.Position = RelativePositions[RootPositionProp]
				Props.AbsolutePositon = ElementAbsolutePosition

				for PropName, PropValue in next, PositionProps do
					Props[PropName] = PropValue
					Props["Absolute" .. PropName] = AbsolutePositions[PropName]
				end
				debug.profileend()

				debug.profilebegin("Update children")
				for ChildElement in next, self._Children do
					ChildElement:_UpdatePosition(ElementAbsolutePosition)
				end
				debug.profileend()
			end
		end

		function GuiObject:GetFullName()
			return self._FullName
		end
		function GuiObject:Destroy()
			debug.profilebegin("namecall_Destroy")
			self._DrawingObject:Remove()

			for _, Connection in next, self._Connections do
				Connection:DisconnectAll()
			end
			for Child in next, self._Children do
				Child:Destroy()
			end

			local Parent = self._Properties.Parent
			if Parent ~= UNDEFINED then
				Parent._Children[self] = nil
			end

			table.clear(self._Connections)
			table.clear(self._Children)
			self._Destroyed = true

			debug.profileend()
		end
		function GuiObject:GetChildren()
			debug.profilebegin("namecall_GetChildren")
			local Children = {}
			for Child in next, self._Children do
				table.insert(Children, Child)
			end

			return Children, debug.profileend()
		end
		function GuiObject:GetDescendants()
			debug.profilebegin("namecall_GetDescendants")
			return RecursiveFlatten({}, 0, self._Children), debug.profileend()
		end
		function GuiObject:FindFirstChild(Name)
			for Object in next, self._Children do
				if Object._Properties.Name == Name then
					return Object
				end
			end
		end
		function GuiObject:GetDebugId()
			return self._DebugId
		end
	end

	-- https://x.synapse.to/docs/reference/drawing_lib.html#square
	local Square do
		Square = {}

		local ClassPropertiesDraft = {
			Thickness = 1,
			Filled = false,
			Class = "Square"
		}
		local ReadOnlyProps = {}
		DrawingElement.ClassProperties.Square = ClassPropertiesDraft

		function Square.new()
			local DrawingObject = Drawing.new("Square")
			local ParentClass = GuiObject.new()

			local Properties = setmetatable(DeepCopy(ClassPropertiesDraft), {
				-- Properties inherited from parent GuiObject class
				__index = ParentClass._Properties
			})

			local Data = {
				_ParentClass = ParentClass,
				_Properties = Properties,
				_DrawingObject = DrawingObject,

				_Children = {}, -- [Element] = true
			}

			-- Copy over data from inheriting class onto child class
			for Key, Value in next, ParentClass do
				if Key ~= "_Properties" then
					Data[Key] = Value
				end
			end

			local Object = setmetatable(Data, setmetatable(Square, ParentClass))
			return Object
		end

		function Square:__index(Key)
			debug.profilebegin("Square.__index " .. Key)
			local FoundProp = self._Properties[Key] or Square[Key] or self._ParentClass[Key]
			if FoundProp == nil then
				error(Error.InvalidProperty:format(tostring(Key), self.Class, self.Name))
			elseif FoundProp == UNDEFINED then
				debug.profileend()
				return nil
			end

			debug.profileend()
			return FoundProp
		end
		function Square:__newindex(Key, Value)
			debug.profilebegin("Square.__newindex " .. Key)

			if self._Destroyed then
				error(Error.DestroyedSet:format(tostring(Key), tostring(self._Properties.Name)))
			elseif ReadOnlyProps[Key] then
				error(Error.ReadOnlySet:format(tostring(Key)))
			elseif Key == "Position" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self:_UpdatePosition(nil, Value)
			elseif Key == "Size" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self._Properties.Size = Value
				self._DrawingObject.Size = Value
			elseif Key == "Filled" then
				assert(type(Value) == "boolean", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self._Properties.Filled = Value
				self._DrawingObject.Filled = Value
			else
				GuiObject.__newindex(self, Key, Value)
			end

			debug.profileend()
		end

		-- Called whenever `Square` changes parent or has its `Position` property updated
		function Square:_UpdatePosition(ParentPosition, NewPosition)
			return GuiObject._UpdatePosition(self, ParentPosition, "Position", {
				Position = NewPosition or UNDEFINED
			})
		end

		setmetatable(Square, GuiObject)
		ElementClasses.Square = Square
	end

	-- https://x.synapse.to/docs/reference/drawing_lib.html#line
	local Line do
		Line = {
			Class = "Line"
		}

		local ClassPropertiesDraft = {
			Thickness = 1,
			From = Vector2.new(0, 0),
			To = Vector2.new(0, 0),
			AbsoluteFrom = Vector2.new(0, 0),
			AbsoluteTo = Vector2.new(0, 0)
		}
		local ReadOnlyProps = {
			Position = true,
			AbsoluteFrom = true,
			AbsoluteTo = true
		}
		DrawingElement.ClassProperties.Line = ClassPropertiesDraft

		function Line.new()
			local DrawingObject = Drawing.new("Line")
			local ParentClass = GuiObject.new()

			local Properties = setmetatable(DeepCopy(ClassPropertiesDraft), {
				-- Properties inherited from parent GuiObject class
				__index = ParentClass._Properties
			})

			local Data = {
				_ParentClass = ParentClass,
				_Properties = Properties,
				_DrawingObject = DrawingObject,

				_Children = {}, -- [Element] = true
			}

			-- Copy over data from inheriting class onto child class
			for Key, Value in next, ParentClass do
				if Key ~= "_Properties" then
					Data[Key] = Value
				end
			end

			local Object = setmetatable(Data, setmetatable(Line, ParentClass))
			return Object
		end

		function Line:__index(Key)
			debug.profilebegin("Line.__index " .. tostring(Key))
			local FoundProp = self._Properties[Key] or Line[Key] or self._ParentClass[Key]
			if FoundProp == nil then
				error(Error.InvalidProperty:format(tostring(Key), self.Class, self.Name))
			elseif FoundProp == UNDEFINED then
				return nil, debug.profileend()
			end

			return FoundProp, debug.profileend()
		end
		function Line:__newindex(Key, Value)
			debug.profilebegin("Line.__newindex " .. tostring(Key))

			if self._Destroyed then
				error(Error.DestroyedSet:format(tostring(Key), tostring(self._Properties.Name)))
			elseif ReadOnlyProps[Key] then
				error(Error.ReadOnlySet:format(tostring(Key)))
			elseif Key == "From" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self:_UpdatePosition(nil, Value)
			elseif Key == "To" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self:_UpdatePosition(nil, nil, Value)
			else
				GuiObject.__newindex(self, Key, Value)
			end

			debug.profileend()
		end

		-- Called whenever `Line` changes parent or has its `From` or `To` properties updated
		function Line:_UpdatePosition(ParentPosition, NewFrom, NewTo)
			return GuiObject:_UpdatePosition(ParentPosition, "From", {
				From = NewFrom or UNDEFINED,
				To = NewTo or UNDEFINED,
			})
		end

		setmetatable(Line, GuiObject)
		ElementClasses.Line = Line
	end

	-- https://x.synapse.to/docs/reference/drawing_lib.html#text
	local Text do
		Text = {}

		local ClassPropertiesDraft = {
			Text = "",
			TextSize = 16, -- Equivalent to `Drawing.new("Text").Size`
			Center = false,
			Outline = false,
			OutlineColor = Color3.new(0, 0, 0),
			TextBounds = Vector2.new(0, 16),
			Font = Drawing.Fonts.UI,
			Size = Vector2.new(),
			Class = "Text"
		}
		local ReadOnlyProps = {
			TextBounds = true,
		}
		DrawingElement.ClassProperties.Text = ClassPropertiesDraft

		function Text.new()
			local DrawingObject = Drawing.new("Text")
			local ParentClass = GuiObject.new()

			local Properties = setmetatable(DeepCopy(ClassPropertiesDraft), {
				-- Properties inherited from parent GuiObject class
				__index = ParentClass._Properties
			})

			local Data = {
				_ParentClass = ParentClass,
				_Properties = Properties,
				_DrawingObject = DrawingObject,

				_Children = {}, -- [Element] = true
			}

			-- Copy over data from inheriting class onto child class
			for Key, Value in next, ParentClass do
				if Key ~= "_Properties" then
					Data[Key] = Value
				end
			end

			local Object = setmetatable(Data, setmetatable(Text, ParentClass))
			return Object
		end

		function Text:__index(Key)
			debug.profilebegin("Text.__index " .. tostring(Key))
			local FoundProp = self._Properties[Key] or Text[Key] or self._ParentClass[Key]
			if FoundProp == nil then
				error(Error.InvalidProperty:format(tostring(Key), self.Class, self.Name))
			elseif FoundProp == UNDEFINED then
				return nil, debug.profileend()
			end

			return FoundProp, debug.profileend()
		end
		function Text:__newindex(Key, Value)
			debug.profilebegin("Text.__newindex " .. tostring(Key))

			if self._Destroyed then
				error(Error.DestroyedSet:format(tostring(Key), tostring(self._Properties.Name)))
			elseif ReadOnlyProps[Key] then
				error(Error.ReadOnlySet:format(tostring(Key)))
			elseif Key == "Position" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self:_UpdatePosition(nil, Value)
			elseif Key == "Size" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self._Properties.Size = Value
			elseif Key == "Text" then
				self._Properties.Text = Value
				self._DrawingObject.Text = Value
				self._Properties.TextBounds = self._DrawingObject.TextBounds
			else
				GuiObject.__newindex(self, Key, Value)
			end

			debug.profileend()
		end

		-- Called whenever `Text` changes parent or has its `Position` property updated
		function Text:_UpdatePosition(ParentPosition, NewPosition)
			return GuiObject._UpdatePosition(self, ParentPosition, "Position", {
				Position = NewPosition or UNDEFINED
			})
		end

		setmetatable(Text, GuiObject)
		ElementClasses.Text = Text
	end

	-- https://x.synapse.to/docs/reference/drawing_lib.html#line
	local Triangle do
		Triangle = {
			Class = "Triangle"
		}

		local ClassPropertiesDraft = {
			Thickness = 1,
			PointA = Vector2.new(),
			PointB = Vector2.new(),
			PointC = Vector2.new(),
			AbsolutePointA = Vector2.new(),
			AbsolutePointB = Vector2.new(),
			AbsolutePointC = Vector2.new(),
			Filled = false,
		}
		local ReadOnlyProps = {
			AbsolutePointA = Vector2.new(),
			AbsolutePointB = Vector2.new(),
			AbsolutePointC = Vector2.new(),
		}
		DrawingElement.ClassProperties.Triangle = ClassPropertiesDraft

		function Triangle.new()
			local DrawingObject = Drawing.new("Triangle")
			local ParentClass = GuiObject.new()

			local Properties = setmetatable(DeepCopy(ClassPropertiesDraft), {
				-- Properties inherited from parent GuiObject class
				__index = ParentClass._Properties
			})

			local Data = {
				_ParentClass = ParentClass,
				_Properties = Properties,
				_DrawingObject = DrawingObject,

				_Children = {}, -- [Element] = true
			}

			-- Copy over data from inheriting class onto child class
			for Key, Value in next, ParentClass do
				if Key ~= "_Properties" then
					Data[Key] = Value
				end
			end

			local Object = setmetatable(Data, setmetatable(Triangle, ParentClass))
			return Object
		end

		function Triangle:__index(Key)
			debug.profilebegin("Triangle_index_" .. tostring(Key))
			local FoundProp = self._Properties[Key] or Triangle[Key] or self._ParentClass[Key]
			if FoundProp == nil then
				error(Error.InvalidProperty:format(tostring(Key), self.Class, self.Name))
			elseif FoundProp == UNDEFINED then
				return nil, debug.profileend()
			end

			return FoundProp, debug.profileend()
		end
		function Triangle:__newindex(Key, Value)
			debug.profilebegin("Triangle.__newindex " .. tostring(Key))

			if self._Destroyed then
				error(Error.DestroyedSet:format(tostring(Key), tostring(self._Properties.Name)))
			elseif ReadOnlyProps[Key] then
				error(Error.ReadOnlySet:format(tostring(Key)))
			elseif Key == "PointA" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self:_UpdatePosition(nil, Value)
			elseif Key == "PointB" or Key == "Position" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self:_UpdatePosition(nil, nil, Value)
			elseif Key == "PointC" then
				assert(typeof(Value) == "Vector2", Error.InvalidSet:format(tostring(Key), "Vector2", tostring(Value)))
				self:_UpdatePosition(nil, nil, nil, Value)
			elseif ClassPropertiesDraft[Key] then
				local ExpectedType = typeof(ClassPropertiesDraft[Key])
				assert(typeof(Value) == ExpectedType, Error.InvalidValue:format(tostring(Key), ExpectedType, typeof(Value)))
				self._Properties[Key] = Value
				self._DrawingObject[Key] = Value
			else
				GuiObject.__newindex(self, Key, Value)
			end

			debug.profileend()
		end

		-- Called whenever `Triangle` changes parent or has its `PointA`, `PointB` or `PointC` properties updated
		function Triangle:_UpdatePosition(ParentPosition, NewA, NewB, NewC)
			return GuiObject._UpdatePosition(self, ParentPosition, "PointA", {
				PointA = NewA or UNDEFINED,
				PointB = NewB or UNDEFINED,
				PointC = NewC or UNDEFINED,
			})
		end

		setmetatable(Triangle, GuiObject)
		ElementClasses.Triangle = Triangle
	end

	function DrawingElement.new(Class)
		assert(type(Class) == "string", "bad argument #1 to 'DrawingElement.new' (string expected, got " .. typeof(Class) .. ")")
		assert(ElementClasses[Class] ~= nil, "Unable to create DrawingElement of type '" .. Class .. "'")

		return ElementClasses[Class].new()
	end

	DrawingElement.ClassProperties = setmetatable(DrawingElement.ClassProperties, {
		__index = DrawingElement.ClassProperties.GuiObject
	})
	GlobalEnv.DrawingElement = DrawingElement
end

local ElementTweenService do

end