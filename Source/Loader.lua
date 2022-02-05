if getgenv()._DrawingEnvironment ~= nil then
	warn("An instance of DrawingElement API is already running!")
	--return
end

local ScriptPath = "https://raw.githubusercontent.com/PysephRBX/DrawingElement/main/Source/%s.lua"
local function RequireScript(ScriptName)
	return loadstring(game:HttpGet(string.format(ScriptPath, ScriptName)))
end

getgenv()._DrawingEnvironment = {
	Signal = RequireScript("Signal"),
	ClassAPI = RequireScript("ClassAPI"),
}

getgenv().DrawingElement = RequireScript("DrawingElement")