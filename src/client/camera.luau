-- Scriptable top-down camera: north-up, WASD/arrows/middle-drag to pan,
-- mouse wheel to zoom. Flat FOV to keep the "map" feel.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local CameraRig = {}

local cam
local height = 350
local center = Vector2.new(0, 30)
local MIN_H, MAX_H = 150, 820
local PAN_LIMIT = 950

function CameraRig.zoomBy(delta)
	if delta > 0 then
		height = math.max(MIN_H, height * 0.88)
	else
		height = math.min(MAX_H, height * 1.14)
	end
end

local function apply(dt)
	-- self-heal: Studio/tests may recreate CurrentCamera; keep writing to the live one
	if workspace.CurrentCamera ~= cam then
		cam = workspace.CurrentCamera
		if not cam then return end
		cam.CameraType = Enum.CameraType.Scriptable
	end

	local speed = height * 1.15
	local move = Vector2.new()
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		move = move + Vector2.new(0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		move = move + Vector2.new(0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		move = move + Vector2.new(-1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		move = move + Vector2.new(1, 0)
	end
	center = center + move * speed * dt
	center = Vector2.new(math.clamp(center.X, -PAN_LIMIT, PAN_LIMIT), math.clamp(center.Y, -PAN_LIMIT, PAN_LIMIT))

	cam.CFrame = CFrame.lookAt(
		Vector3.new(center.X, height, center.Y),
		Vector3.new(center.X, 0, center.Y),
		Vector3.new(0, 0, -1)
	)
	cam.FieldOfView = 30
end

function CameraRig.init()
	cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable

	-- middle-mouse drag panning
	local dragging = false
	local lastPos = nil
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = true
			lastPos = UserInputService:GetMouseLocation()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
			lastPos = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement and lastPos then
			local now = UserInputService:GetMouseLocation()
			local delta = (now - lastPos) * (height / 430)
			center = center + Vector2.new(delta.X, delta.Y)
			center = Vector2.new(math.clamp(center.X, -PAN_LIMIT, PAN_LIMIT), math.clamp(center.Y, -PAN_LIMIT, PAN_LIMIT))
			lastPos = now
		end
	end)

	RunService:BindToRenderStep("TopDownCamera", Enum.RenderPriority.Camera.Value + 1, apply)
end

-- World point under the mouse on the y=0 plane (pure math, no raycast).
-- GetMouseLocation returns SCREEN coords (incl. GUI inset) -> ScreenPointToRay.
function CameraRig.groundPoint()
	local loc = UserInputService:GetMouseLocation()
	local ray = cam:ScreenPointToRay(loc.X, loc.Y)
	if math.abs(ray.Direction.Y) < 1e-5 then
		return nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
	if t < 0 then
		return nil
	end
	return Vector2.new(ray.Origin.X + ray.Direction.X * t, ray.Origin.Z + ray.Direction.Z * t)
end

return CameraRig
