local Environment = getgenv()._DrawingEnvironment

if Environment ~= nil then
	warn("DrawingExtension API is already running!")
	--return
end

local function RequireScript(ScriptName)

end

local Environment = {
	Signal = RequireScript("Signal")
}

getgenv()._DrawingEnvironment = Environment

RequireScript("Loader")