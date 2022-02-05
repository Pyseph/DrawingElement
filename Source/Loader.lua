if getgenv()._DrawingEnvironment ~= nil then
	warn("DrawingExtension API is already running!")
	--return
end

local ScriptPath = "https://raw.githubusercontent.com/PysephRBX/DrawingElement/main/Source/%s.lua"
local function RequireScript(ScriptName)
	return loadstring(game:HttpGet(string.format(ScriptPath, ScriptName)))
end

local Environment = {
	Signal = RequireScript("Signal")
}

getgenv()._DrawingEnvironment = Environment

RequireScript("DrawingElement")