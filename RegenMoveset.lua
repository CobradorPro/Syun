-- StarterPlayer > StarterPlayerScripts > RegenMoveset (LocalScript)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local GhostRemote = ReplicatedStorage:WaitForChild("RegenRemotes"):WaitForChild("Ghost")

------------------------------------------------------------------ CONFIG
local CFG = {
	Cooldown = { Jump = 6, Noclip = 10, Grapple = 4 },
	NoclipTime = 3, NoclipSpeed = 18,
	GrappleRange = 140, GrappleSpeed = 85,
	MaxDrops = 40,
}
local LOW = UIS.TouchEnabled and not UIS.KeyboardEnabled
local Q = LOW and { strands = 2, segs = 7, frags = 2 } or { strands = 3, segs = 11, frags = 4 }
local COL = {
	Energy = Color3.fromRGB(225, 58, 52), Hot = Color3.fromRGB(255, 170, 140),
	Core = Color3.fromRGB(236, 226, 210), Muscle = Color3.fromRGB(150, 30, 38),
	MuscleHot = Color3.fromRGB(205, 62, 58), Blood = Color3.fromRGB(165, 16, 28),
	Dust = Color3.fromRGB(150, 140, 130),
}
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

------------------------------------------------------------------ MATH
local PI = math.pi
local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end
local function lerp(a, b, t) return a + (b - a) * t end
local function inv(a, b, x) return clamp01((x - a) / (b - a)) end
local function smooth(a, b, x) local t = inv(a, b, x) return t * t * (3 - 2 * t) end
local function outCubic(x) x = clamp01(x) return 1 - (1 - x) ^ 3 end
local function outBack(x, k) x = clamp01(x) k = k or 1.5 local i = x - 1 return 1 + (k + 1) * i ^ 3 + k * i * i end
local function spring(x) x = clamp01(x) if x >= 1 then return 1 end return 1 - math.exp(-6.5 * x) * math.cos(11 * x) end
local function bell(x) return math.sin(PI * clamp01(x)) end
local function rand(a, b) return a + math.random() * (b - a) end
local function flat(v) v = Vector3.new(v.X, 0, v.Z) return v.Magnitude > 1e-3 and v.Unit or Vector3.zAxis end

------------------------------------------------------------------ MAID
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ t = {} }, Maid) end
function Maid:Add(x) table.insert(self.t, x) return x end
function Maid:Clean()
	for i = #self.t, 1, -1 do
		local x = self.t[i]
		if typeof(x) == "RBXScriptConnection" then x:Disconnect()
		elseif typeof(x) == "Instance" then x:Destroy()
		elseif type(x) == "function" then pcall(x) end
	end
	table.clear(self.t)
end

------------------------------------------------------------------ STATE
local S = { gen = 0, busy = nil, cd = {}, char = nil, hum = nil, root = nil, r6 = false }

local function alive(gen)
	return S.gen == gen and S.hum and S.hum.Health > 0 and S.root and S.root.Parent ~= nil
end

-- Linha do tempo: fn(p, elapsed). Cancela com erro "CANCEL" em morte/respawn.
local function Animate(ctx, dur, fn)
	local t0 = os.clock()
	while true do
		if not alive(ctx.gen) then error("CANCEL", 0) end
		local e = os.clock() - t0
		local p = dur > 0 and clamp01(e / dur) or 1
		fn(p, e)
		if p >= 1 then break end
		RunService.RenderStepped:Wait()
	end
end
local function Wait(ctx, s) Animate(ctx, s, function() end) end

------------------------------------------------------------------ RIG
local GROUPS_R6 = { Torso = { "Torso" }, Head = { "Head" }, LArm = { "Left Arm" }, RArm = { "Right Arm" }, LLeg = { "Left Leg" }, RLeg = { "Right Leg" } }
local GROUPS_R15 = {
	Torso = { "LowerTorso", "UpperTorso" }, Head = { "Head" },
	LArm = { "LeftUpperArm", "LeftLowerArm", "LeftHand" }, RArm = { "RightUpperArm", "RightLowerArm", "RightHand" },
	LLeg = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" }, RLeg = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}
local function Group(name)
	local out = {}
	for _, n in ipairs((S.r6 and GROUPS_R6 or GROUPS_R15)[name]) do
		local p = S.char:FindFirstChild(n)
		if p and p:IsA("BasePart") then table.insert(out, p) end
	end
	return out
end
local function Concat(...)
	local out = {}
	for _, l in ipairs({ ... }) do for _, v in ipairs(l) do table.insert(out, v) end end
	return out
end

-- withAcc: true = todos acessórios | "attached" = só os presos às partes
local function Capture(parts, withAcc)
	local orig, set = {}, {}
	local function cap(x)
		if x:IsA("BasePart") or x:IsA("Decal") then orig[x] = x.Transparency end
	end
	local function capTree(r) cap(r) for _, d in ipairs(r:GetDescendants()) do cap(d) end end
	for _, p in ipairs(parts) do set[p] = true capTree(p) end
	if withAcc then
		for _, a in ipairs(S.char:GetChildren()) do
			if a:IsA("Accessory") then
				local h = a:FindFirstChild("Handle")
				local w = h and h:FindFirstChildWhichIsA("JointInstance")
				local to = w and (w.Part0 == h and w.Part1 or w.Part0)
				if h and (withAcc == true or set[to]) then capTree(h) end
			end
		end
	end
	return orig
end
local function SetVis(orig, hidden, filter)
	for x, o in pairs(orig) do
		if x.Parent and (not filter or filter(x)) then
			local v = o + (1 - o) * hidden
			if math.abs(x.Transparency - v) > 0.002 then x.Transparency = v end
		end
	end
end

------------------------------------------------------------------ FX
local function NewCtx(gen)
	local ctx = { gen = gen, maid = Maid.new(), drops = 0 }
	local f = Instance.new("Folder")
	f.Name = "RegenFX_Local"
	f.Parent = Workspace
	ctx.folder = ctx.maid:Add(f)
	local carrier = Instance.new("Part")
	carrier.Anchored, carrier.CanCollide, carrier.CanQuery, carrier.CanTouch = true, false, false, false
	carrier.Transparency, carrier.Size, carrier.Parent = 1, Vector3.new(0.2, 0.2, 0.2), f
	ctx.carrier = carrier
	local function em(props)
		local e = Instance.new("ParticleEmitter")
		e.Rate, e.LightInfluence = 0, 0
		for k, v in pairs(props) do e[k] = v end
		e.Parent = carrier
		return e
	end
	ctx.spark = em({
		Texture = TEX_SPARK, LightEmission = 1, Drag = 6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0, 1), Lifetime = NumberRange.new(0.25, 0.55),
		Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180),
	})
	ctx.dust = em({
		Texture = TEX_SMOKE, Color = ColorSequence.new(COL.Dust), LightInfluence = 0.8,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(3, 6), Drag = 4,
		SpreadAngle = Vector2.new(80, 10), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
	})
	return ctx
end

local function FXPart(ctx, color, material, shape)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color, p.Transparency, p.Size = color, 1, Vector3.new(0.05, 0.05, 0.05)
	if shape then p.Shape = shape end
	p.Parent = ctx.folder
	return p
end
local function Put(p, cf, size, alpha, color)
	if alpha >= 0.995 then p.Transparency = 1 return end
	p.Transparency = alpha
	p.Size = Vector3.new(math.max(size.X, 0.02), math.max(size.Y, 0.02), math.max(size.Z, 0.02))
	p.CFrame = cf
	if color then p.Color = color end
end
local function Burst(ctx, pos, n, color)
	ctx.carrier.CFrame = CFrame.new(pos)
	ctx.spark.Color = ColorSequence.new(color or COL.Hot, COL.Energy)
	ctx.spark:Emit(n)
end
local function Dust(ctx, pos, n)
	ctx.carrier.CFrame = CFrame.new(pos)
	ctx.dust:Emit(n)
end
-- gotinha física (estilizada)
local function Drop(ctx, pos, vel, size)
	if ctx.drops >= CFG.MaxDrops then return end
	ctx.drops += 1
	local d = Instance.new("Part")
	d.Shape = Enum.PartType.Ball
	d.Size = Vector3.one * (size or rand(0.12, 0.24))
	d.Color, d.Material = COL.Blood, Enum.Material.Glass
	d.CanQuery, d.CanTouch, d.CastShadow, d.Massless = false, false, false, true
	d.CFrame = CFrame.new(pos)
	d.Parent = ctx.folder
	d.AssemblyLinearVelocity = vel
	TweenService:Create(d, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.one * 0.02 }):Play()
	Debris:AddItem(d, 1.15)
	task.delay(1.15, function() ctx.drops -= 1 end)
end
local function Shake(hum, power, dur)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur and hum.Parent do
			local k = power * (1 - (os.clock() - t0) / dur)
			hum.CameraOffset = Vector3.new(rand(-k, k), rand(-k, k), rand(-k, k))
			RunService.RenderStepped:Wait()
		end
		if hum.Parent then hum.CameraOffset = Vector3.zero end
	end)
end
local function RayParams(ctx)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { S.char, ctx.folder }
	return rp
end
local function GroundBelow(ctx, pos, depth)
	local r = Workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -(depth or 60), 0), RayParams(ctx))
	return r and r.Position or (pos - Vector3.new(0, 3, 0))
end

------------------------------------------------------------------ RECONSTRUÇÃO
-- entries: { parts, t0, dur, mode = "limb"|"center", stagger }
-- Estágios por parte: núcleo estrutural -> volume muscular (mola) -> superfície real.
local function Rebuild(ctx, orig, entries, onFrame)
	local jobs, tEnd = {}, 0
	for _, e in ipairs(entries) do
		for i, p in ipairs(e.parts) do
			local j = {
				p = p, t0 = e.t0 + (i - 1) * (e.stagger or 0), dur = e.dur, mode = e.mode,
				core = FXPart(ctx, COL.Core), mus = FXPart(ctx, COL.Muscle),
				ring = FXPart(ctx, COL.Hot, Enum.Material.Neon), orig = orig[p] or 0, fired = false,
			}
			table.insert(jobs, j)
			tEnd = math.max(tEnd, j.t0 + j.dur)
		end
	end
	Animate(ctx, tEnd, function(_, t)
		local clock = os.clock()
		for _, j in ipairs(jobs) do
			local p = j.p
			local g = (t - j.t0) / j.dur
			if g <= 0 or not p.Parent then
				j.core.Transparency, j.mus.Transparency, j.ring.Transparency = 1, 1, 1
			else
				local sz, base = p.Size, p.CFrame
				local limb = j.mode == "limb"
				local top = limb and sz.Y / 2 or 0
				-- 1) núcleo: estende a partir da junta, com tremor na ponta
				local cg = smooth(0, 0.45, g)
				local cl = sz.Y * cg
				local wob = (1 - cg) * 0.05
				local coreCF = base * CFrame.new(0, limb and (top - cl / 2) or 0, 0)
					* CFrame.Angles(math.noise(clock * 2, j.t0) * wob, 0, math.noise(clock * 2, j.t0 + 9) * wob)
				local cw = limb and 0.24 or 0.32
				Put(j.core, coreCF, Vector3.new(sz.X * cw, cl, sz.Z * cw), lerp(0.35, 0, smooth(0, 0.2, g)) + smooth(0.6, 0.8, g),
					COL.Hot:Lerp(COL.Core, smooth(0.1, 0.5, g)))
				-- frente de ossificação
				if cg < 1 then
					local ry = limb and (top - cl) or (cl / 2)
					Put(j.ring, base * CFrame.new(0, ry, 0), Vector3.new(sz.X * 0.42, 0.05, sz.Z * 0.42), 0.25)
				else
					j.ring.Transparency = 1
				end
				-- 2) volume muscular: incha com overshoot, pulsa e contrai
				local mg = inv(0.25, 0.8, g)
				local sg = smooth(0.7, 1, g)
				if mg > 0 then
					local ml = sz.Y * outCubic(inv(0.25, 0.7, g))
					local pulse = 1 + 0.05 * math.sin(clock * 11 + j.t0 * 3) * (1 - sg)
					local xz = lerp(0.3, 0.97, spring(mg)) * pulse
					local mcf = base * CFrame.new(0, limb and (top - ml / 2) or 0, 0)
					Put(j.mus, mcf, Vector3.new(sz.X * xz, ml * (1 - 0.04 * bell(mg)), sz.Z * xz),
						math.max(lerp(0.6, 0.08, smooth(0, 0.3, mg)), sg),
						COL.MuscleHot:Lerp(COL.Muscle, smooth(0, 0.6, mg)):Lerp(p.Color, sg))
				else
					j.mus.Transparency = 1
				end
				-- 3) superfície: a parte real volta
				p.Transparency = j.orig + (1 - j.orig) * (1 - sg)
				if not j.fired and g >= 0.72 then
					j.fired = true
					Burst(ctx, base.Position, 6)
				end
			end
		end
		if onFrame then onFrame(t, tEnd) end
	end)
	for _, j in ipairs(jobs) do j.core:Destroy() j.mus:Destroy() j.ring:Destroy() end
end

-- Tendões/fibras entre dois pontos (reutilizável)
local function NewTendons(ctx)
	local T = { strands = {} }
	for k = 1, Q.strands + 1 do
		local nerve = k == Q.strands + 1
		local segs = {}
		for i = 1, Q.segs do
			segs[i] = FXPart(ctx, nerve and COL.Hot or (k % 2 == 0 and COL.MuscleHot or COL.Muscle),
				nerve and Enum.Material.Neon or Enum.Material.SmoothPlastic)
		end
		T.strands[k] = { segs = segs, nerve = nerve, phase = k * 2.1, side = rand(-1, 1) }
	end
	return T
end
local function DrawTendons(T, a, b, sag, amp, thick, alpha)
	local dir = b - a
	local len = dir.Magnitude
	if len < 0.05 then
		for _, s in ipairs(T.strands) do for _, p in ipairs(s.segs) do p.Transparency = 1 end end
		return {}
	end
	local u = dir.Unit
	local side = u:Cross(Vector3.yAxis)
	side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
	local up = side:Cross(u)
	local clock = os.clock()
	local pts
	for _, s in ipairs(T.strands) do
		local n = #s.segs
		local prev = a
		pts = {}
		for i = 1, n do
			local f = i / n
			local env = bell(f)
			local w = math.sin(f * PI * 3 + clock * 9 + s.phase) * amp * env
			local w2 = math.cos(f * PI * 2 + clock * 7 + s.phase) * amp * 0.6 * env
			local pt = a + dir * f - Vector3.new(0, sag * env, 0)
				+ side * (w + s.side * 0.12 * env) + up * w2
			local mid = (prev + pt) / 2
			local sl = (pt - prev).Magnitude
			local th = (s.nerve and 0.045 or thick) * (1 - 0.35 * env)
			Put(s.segs[i], CFrame.lookAt(mid, pt), Vector3.new(th, th, sl + th * 0.5), alpha)
			pts[i] = pt
			prev = pt
		end
	end
	return pts
end

------------------------------------------------------------------ HABILIDADE 1: JUMP
local function AbilityJump(ctx)
	local hum, root = S.hum, S.root
	local legs = Concat(Group("LLeg"), Group("RLeg"))
	local orig = Capture(legs, "attached")
	ctx.maid:Add(function() SetVis(orig, 0) end)
	ctx.maid:Add(function()
		if root.Parent then root.Anchored = false end
		if hum.Parent then hum.PlatformStand = false end
	end)

	local look = flat(root.CFrame.LookVector)
	local standOffset = S.r6 and 3 or (hum.HipHeight + root.Size.Y / 2)

	-- Antecipação: agacha e inclina
	root.Anchored = true
	local base = root.CFrame
	Animate(ctx, 0.2, function(p)
		local k = outCubic(p)
		root.CFrame = base * CFrame.new(0, -0.7 * k, 0) * CFrame.Angles(-0.18 * k, 0, 0)
	end)
	Dust(ctx, base.Position - Vector3.new(0, standOffset, 0), 6)
	root.Anchored = false
	hum.PlatformStand = true
	root.AssemblyLinearVelocity = look * 9 + Vector3.new(0, 64, 0)
	Shake(hum, 0.15, 0.2)

	-- Desprendimento das pernas durante a subida
	Wait(ctx, 0.14)
	SetVis(orig, 1)
	local debrisLegs = {}
	for _, p in ipairs(legs) do
		local c = p:Clone()
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("Attachment") then d:Destroy() end
		end
		c.Transparency, c.Anchored, c.CanCollide, c.CanQuery, c.Massless = orig[p] or 0, false, true, false, false
		c.CFrame = p.CFrame
		c.Parent = ctx.folder
		c.AssemblyLinearVelocity = root.AssemblyLinearVelocity * 0.25 + Vector3.new(rand(-3, 3), -6, rand(-3, 3))
		c.AssemblyAngularVelocity = Vector3.new(rand(-8, 8), rand(-4, 4), rand(-8, 8))
		table.insert(debrisLegs, c)
		local hip = p.CFrame * Vector3.new(0, p.Size.Y / 2, 0)
		Burst(ctx, hip, 8)
		for _ = 1, 5 do Drop(ctx, hip, Vector3.new(rand(-6, 6), rand(2, 9), rand(-6, 6))) end
	end
	-- perda de equilíbrio: tomba para trás
	root.AssemblyAngularVelocity = root.CFrame.RightVector * 5.5

	-- Queda até o chão
	local rp = RayParams(ctx)
	for _, c in ipairs(debrisLegs) do rp:AddToFilter(c) end
	local hit
	local fallStart = os.clock()
	Animate(ctx, 3, function(p)
		if hit then return end
		local r = Workspace:Raycast(root.Position, Vector3.new(0, -2.2, 0), rp)
		if r and root.AssemblyLinearVelocity.Y < 0 and os.clock() - fallStart > 0.35 then hit = r end
		if os.clock() - fallStart < 3 and not hit then
			-- gotas trilhando a queda
			if math.random() < 0.25 then Drop(ctx, root.Position - root.CFrame.UpVector, Vector3.new(0, 2, 0)) end
		end
	end)
	-- Animate roda 3 s no máximo; se tocou antes, o restante é só espera curta
	local ground = hit and hit.Position or GroundBelow(ctx, root.Position)

	-- Impacto deitado de costas
	root.Anchored = true
	local lieTop = flat(look)
	local lyingPos = Vector3.new(root.Position.X, ground.Y + 0.55, root.Position.Z)
	local lying = CFrame.lookAt(lyingPos, lyingPos + Vector3.yAxis, lieTop)
	local from = root.CFrame
	Animate(ctx, 0.16, function(p) root.CFrame = from:Lerp(lying, p * p) end)
	Dust(ctx, ground, 14)
	Burst(ctx, lyingPos, 10, COL.Hot)
	Shake(hum, 0.45, 0.35)
	Animate(ctx, 0.45, function(p)
		local b = bell(p) * (1 - p)
		root.CFrame = CFrame.new(0, 0.35 * b, 0) * lying * CFrame.Angles(0.12 * b, 0, 0.06 * math.sin(p * PI * 3) * (1 - p))
	end)

	-- Regeneração com o corpo deitado (respiração ofegante)
	local ll, rl = Group("LLeg"), Group("RLeg")
	Rebuild(ctx, orig, {
		{ parts = ll, t0 = 0.2, dur = 2.2, mode = "limb", stagger = 0.45 },
		{ parts = rl, t0 = 0.55, dur = 2.2, mode = "limb", stagger = 0.45 },
	}, function(t)
		local breath = math.sin(t * 5) * 0.035
		root.CFrame = lying * CFrame.new(0, 0, -breath) * CFrame.Angles(breath * 0.6, 0, 0)
		for _, c in ipairs(debrisLegs) do
			if c.Parent then
				local k = smooth(0, 1.4, t)
				c.Transparency = lerp(c.Transparency, 1, k)
				if k >= 1 then c:Destroy() end
			end
		end
	end)
	SetVis(orig, 0)

	-- Levantar: senta (antecipação) -> pausa -> fica de pé com overshoot
	local standPos = Vector3.new(lyingPos.X, ground.Y + standOffset, lyingPos.Z) - look * 0.6
	local stand = CFrame.lookAt(standPos, standPos + look)
	local sit = lying:Lerp(stand, 0.45) * CFrame.new(0, -0.35, 0)
	local c0 = root.CFrame
	Animate(ctx, 0.5, function(p) root.CFrame = c0:Lerp(sit, outCubic(p)) end)
	Wait(ctx, 0.12)
	Animate(ctx, 0.55, function(p) root.CFrame = sit:Lerp(stand, outBack(p, 1.3)) end)
	Dust(ctx, ground, 5)
	root.Anchored = false
	hum.PlatformStand = false
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
end

------------------------------------------------------------------ HABILIDADE 2: NOCLIP
local function BoxBlocked(ctx, cf, size)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { S.char, ctx.folder }
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf, size, op)) do
		if p.CanCollide then return true end
	end
	return false
end

local function AbilityNoclip(ctx)
	local hum, root = S.hum, S.root
	local body = Concat(Group("Torso"), Group("Head"), Group("LArm"), Group("RArm"), Group("LLeg"), Group("RLeg"))
	local orig = Capture(body, true)
	local standOffset = S.r6 and 3 or (hum.HipHeight + root.Size.Y / 2)
	local charSize = Vector3.new(2, standOffset * 2 - 0.4, 1.2)

	GhostRemote:FireServer(true)
	ctx.maid:Add(function() GhostRemote:FireServer(false) end)
	ctx.maid:Add(function() SetVis(orig, 0) end)
	ctx.maid:Add(function()
		if root.Parent then root.Anchored = false end
		if hum.Parent then hum.PlatformStand = false end
	end)

	-- 1) Carga e explosão
	local hl = ctx.maid:Add(Instance.new("Highlight"))
	hl.FillColor, hl.OutlineColor, hl.FillTransparency, hl.OutlineTransparency = COL.Energy, COL.Hot, 1, 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = S.char
	root.Anchored = true
	local base = root.CFrame
	Animate(ctx, 0.35, function(p)
		hl.FillTransparency = 1 - 0.6 * p
		hl.OutlineTransparency = 1 - p
		local tremor = 0.05 * p
		root.CFrame = base * CFrame.new(rand(-tremor, tremor), -0.25 * outCubic(p), rand(-tremor, tremor))
	end)
	Shake(hum, 0.4, 0.3)
	Burst(ctx, root.Position, 24)

	-- 2) Desintegração rápida do centro para fora
	table.sort(body, function(a, b) return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude end)
	for _, p in ipairs(body) do
		local o = orig[p] or 0
		p.Transparency = 1
		for _ = 1, Q.frags do
			local f = Instance.new("Part")
			f.Size = p.Size * rand(0.22, 0.38)
			f.Color = math.random() < 0.5 and p.Color or COL.Blood
			f.Transparency = o
			f.CanQuery, f.CanTouch, f.CastShadow = false, false, false
			f.CFrame = p.CFrame * CFrame.new(rand(-0.4, 0.4) * p.Size.X, rand(-0.4, 0.4) * p.Size.Y, 0)
			f.Parent = ctx.folder
			f.AssemblyLinearVelocity = (f.Position - root.Position).Unit * rand(10, 18) + Vector3.new(0, rand(4, 10), 0)
			f.AssemblyAngularVelocity = Vector3.new(rand(-10, 10), rand(-10, 10), rand(-10, 10))
			TweenService:Create(f, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = Vector3.one * 0.05, Transparency = 1 }):Play()
			Debris:AddItem(f, 0.75)
		end
		Wait(ctx, 0.03)
	end
	SetVis(orig, 1)
	hl.Enabled = false

	-- 3) Poça e 4) concentração em gota
	local ground = GroundBelow(ctx, root.Position)
	local puddle = FXPart(ctx, COL.Blood, Enum.Material.Glass, Enum.PartType.Cylinder)
	local drop = FXPart(ctx, COL.Blood, Enum.Material.Glass, Enum.PartType.Ball)
	local flatCF = function(pos) return CFrame.new(pos) * CFrame.Angles(0, 0, PI / 2) end
	Animate(ctx, 0.4, function(p)
		local d = lerp(0.4, 4.6, outBack(p, 1.2))
		Put(puddle, flatCF(ground + Vector3.new(0, 0.03, 0)), Vector3.new(0.07, d, d), 0.05)
	end)
	local R = 1.25
	Animate(ctx, 0.5, function(p)
		local k = outCubic(p)
		local d = lerp(4.6, 1.3, k)
		Put(puddle, flatCF(ground + Vector3.new(0, 0.03, 0)), Vector3.new(0.07 + 0.1 * k, d, d), 0.05 + 0.4 * k)
		local r = R * spring(p)
		local wob = 0.25 * bell(p)
		Put(drop, CFrame.new(ground + Vector3.new(0, r * 0.4, 0)), Vector3.new(r * (1 + wob), r * (0.8 - wob * 0.6), r * (1 + wob)), 0.05)
	end)
	puddle.Transparency = 1

	-- 5/6) Controle livre da gota (atravessa paredes via CollisionGroup do servidor)
	root.Anchored = false
	hum.PlatformStand = true
	local att = ctx.maid:Add(Instance.new("Attachment"))
	att.Parent = root
	local lv = ctx.maid:Add(Instance.new("LinearVelocity"))
	lv.Attachment0, lv.RelativeTo = att, Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce, lv.VectorVelocity = 1e7, Vector3.zero
	lv.Parent = root
	local ao = ctx.maid:Add(Instance.new("AlignOrientation"))
	ao.Mode, ao.Attachment0 = Enum.OrientationAlignmentMode.OneAttachment, att
	ao.RigidityEnabled, ao.CFrame = true, CFrame.lookAt(Vector3.zero, flat(base.LookVector))
	ao.Parent = root

	local height = root.Position.Y
	local vel, dropPos, dropVel = Vector3.zero, drop.Position, Vector3.zero
	local trailAcc, lastFlat = 0, flat(base.LookVector)
	local last = os.clock()
	local function UpdateDrop(dt, target, squishExtra)
		-- mola viscosa: a gota "arrasta" atrás do alvo
		local acc = (target - dropPos) * 120 - dropVel * 16
		dropVel += acc * dt
		dropPos += dropVel * dt
		local spd = clamp01(Vector3.new(dropVel.X, 0, dropVel.Z).Magnitude / CFG.NoclipSpeed)
		if spd > 0.05 then lastFlat = flat(dropVel) end
		local clock = os.clock()
		local wob = 0.07 * math.sin(clock * 9) + 0.04 * math.sin(clock * 15.3)
		local jig = clamp01(acc.Magnitude / 900) * 0.15
		local sx = R * (1 - 0.18 * spd + wob + jig)
		local sy = R * (0.78 - 0.22 * spd - wob * 0.8 - (squishExtra or 0))
		local sz = R * (1 + 0.55 * spd + jig)
		local lean = CFrame.Angles(-0.25 * spd, 0, 0)
		Put(drop, CFrame.lookAt(dropPos, dropPos + lastFlat) * lean * CFrame.new(0, 0, -0.1 * spd),
			Vector3.new(sx, math.max(sy, 0.25), sz), 0.05)
		return spd
	end

	Animate(ctx, CFG.NoclipTime, function()
		local now = os.clock()
		local dt = math.min(now - last, 0.05)
		last = now
		local want = hum.MoveDirection * CFG.NoclipSpeed
		vel = vel:Lerp(want, 1 - math.exp(-dt * 5))
		lv.VectorVelocity = Vector3.new(vel.X, (height - root.Position.Y) * 8, vel.Z)
		if vel.Magnitude > 0.5 then ao.CFrame = CFrame.lookAt(Vector3.zero, flat(vel)) end
		local target = Vector3.new(root.Position.X, ground.Y + R * 0.38, root.Position.Z)
		local spd = UpdateDrop(dt, target)
		trailAcc += dt * spd
		if trailAcc > 0.08 then
			trailAcc = 0
			local t = FXPart(ctx, COL.Blood, Enum.Material.Glass, Enum.PartType.Cylinder)
			local d0 = rand(0.4, 0.8)
			Put(t, flatCF(Vector3.new(dropPos.X, ground.Y + 0.02, dropPos.Z)), Vector3.new(0.04, d0, d0), 0.1)
			TweenService:Create(t, TweenInfo.new(1), { Size = Vector3.new(0.04, 0.05, 0.05), Transparency = 1 }):Play()
			Debris:AddItem(t, 1.05)
		end
	end)

	-- 7) Saída segura: se estiver dentro de algo, desliza até um espaço livre
	local function standCFAt(pos)
		local g = GroundBelow(ctx, Vector3.new(pos.X, height + 1, pos.Z), 30)
		return CFrame.new(Vector3.new(pos.X, g.Y + standOffset, pos.Z)), g
	end
	local cf, g = standCFAt(root.Position)
	if BoxBlocked(ctx, cf, charSize) then
		local found
		for r = 2, 16, 2 do
			for a = 0, 11 do
				local ang = a / 12 * 2 * PI
				local c2, g2 = standCFAt(root.Position + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r))
				if not BoxBlocked(ctx, c2, charSize) then found = { c2, g2 } break end
			end
			if found then break end
		end
		if found then
			cf, g = found[1], found[2]
			local startPos = root.Position
			Animate(ctx, 0.45, function(p)
				local now = os.clock()
				local dt = math.min(now - last, 0.05)
				last = now
				local pos = startPos:Lerp(Vector3.new(cf.X, height, cf.Z), smooth(0, 1, p))
				lv.VectorVelocity = (pos - root.Position) * 20
				UpdateDrop(dt, Vector3.new(root.Position.X, ground.Y + R * 0.38, root.Position.Z))
			end)
		end
	end
	lv:Destroy() ao:Destroy()
	ground = g

	-- Regeneração em estágios
	local look = flat(ao.CFrame.LookVector)
	local standCF = CFrame.lookAt(cf.Position, cf.Position + look)
	root.Anchored = true
	root.CFrame = standCF
	GhostRemote:FireServer(false)
	-- gota derrete em poça
	local dp = drop.Position
	Animate(ctx, 0.35, function(p)
		local k = outCubic(p)
		Put(drop, CFrame.new(dp:Lerp(ground + Vector3.new(0, 0.1, 0), k)), Vector3.new(R * (1 + k), R * (0.8 - 0.7 * k), R * (1 + k)), 0.05 + 0.9 * k)
		local d = lerp(1, 3.4, outBack(p))
		Put(puddle, flatCF(Vector3.new(standCF.X, ground.Y + 0.03, standCF.Z)), Vector3.new(0.07, d, d), 0.05)
	end)
	drop.Transparency = 1
	Burst(ctx, ground + Vector3.new(0, 1, 0), 14)

	Rebuild(ctx, orig, {
		{ parts = Group("Torso"), t0 = 0.0, dur = 1.5, mode = "center", stagger = 0.2 },
		{ parts = Group("LArm"), t0 = 0.85, dur = 1.6, mode = "limb", stagger = 0.25 },
		{ parts = Group("RArm"), t0 = 0.95, dur = 1.6, mode = "limb", stagger = 0.25 },
		{ parts = Group("LLeg"), t0 = 0.9, dur = 1.6, mode = "limb", stagger = 0.25 },
		{ parts = Group("RLeg"), t0 = 1.0, dur = 1.6, mode = "limb", stagger = 0.25 },
		{ parts = Group("Head"), t0 = 2.1, dur = 1.1, mode = "center" },
	}, function(t, tEnd)
		local k = smooth(0, tEnd * 0.8, t)
		local d = lerp(3.4, 0.2, k)
		Put(puddle, flatCF(Vector3.new(standCF.X, ground.Y + 0.03, standCF.Z)), Vector3.new(0.07, d, d), 0.05 + 0.9 * k)
		root.CFrame = standCF * CFrame.new(0, -0.15 * (1 - k), 0)
	end)

	-- superfície e detalhes (rosto, acessórios)
	hl.Enabled = true
	Animate(ctx, 0.45, function(p)
		SetVis(orig, 1 - smooth(0, 1, p), function(x) return not x:IsA("BasePart") or x.Parent:IsA("Accessory") end)
		hl.FillTransparency = lerp(0.5, 1, p)
		hl.OutlineTransparency = p
	end)
	SetVis(orig, 0)
	root.Anchored = false
	hum.PlatformStand = false
end

------------------------------------------------------------------ HABILIDADE 3: GANCHO
local aimRequest -- função que o input chama com a posição de tela

local function AbilityGrapple(ctx, setAimText)
	local hum, root = S.hum, S.root
	local cam = Workspace.CurrentCamera

	-- Mirar: próximo toque/clique no mundo
	local screenPos
	aimRequest = function(pos) screenPos = pos end
	ctx.maid:Add(function() aimRequest = nil end)
	setAimText(true)
	ctx.maid:Add(function() setAimText(false) end)
	local t0 = os.clock()
	Animate(ctx, 6, function()
		if screenPos or os.clock() - t0 > 6 then return end
	end)
	-- Animate acima roda até 6s; encerramos assim que houver alvo:
	setAimText(false)
	if not screenPos then return false end

	local ray = cam:ScreenPointToRay(screenPos.X, screenPos.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 500, RayParams(ctx))
	if not hit or (hit.Position - root.Position).Magnitude > CFG.GrappleRange then return false end
	local target, normal = hit.Position, hit.Normal

	local arm = Group("RArm")
	local orig = Capture(arm, "attached")
	ctx.maid:Add(function() SetVis(orig, 0) end)
	ctx.maid:Add(function() if hum.Parent then hum.PlatformStand = false end end)
	local top = arm[1]
	local L = 0
	for _, p in ipairs(arm) do L += p.Size.Y end
	local w, d = top.Size.X, top.Size.Z
	local function Shoulder() return (top.CFrame * CFrame.new(0, top.Size.Y / 2 - 0.1, 0)).Position end
	local function ArmCF(shoulderEnd, dir, roll)
		local right = dir:Cross(Vector3.yAxis)
		right = right.Magnitude > 1e-3 and right.Unit or Vector3.xAxis
		local center = shoulderEnd + dir * (L / 2)
		return CFrame.fromMatrix(center, right, dir) * CFrame.Angles(0, roll or 0, 0)
	end

	local fake = FXPart(ctx, top.Color)
	local hand = FXPart(ctx, top.Color:Lerp(Color3.new(0, 0, 0), 0.12))
	local wound = FXPart(ctx, COL.Muscle, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local grip = FXPart(ctx, COL.Blood, Enum.Material.Glass, Enum.PartType.Cylinder)
	local T = NewTendons(ctx)
	local function DrawArm(base, dir, roll, squash, alpha)
		local cf = ArmCF(base, dir, roll)
		Put(fake, cf * CFrame.new(0, 0, 0), Vector3.new(w, L * (squash or 1), d), alpha)
		Put(hand, cf * CFrame.new(0, L * 0.5 * (squash or 1) - 0.18, 0), Vector3.new(w * 1.04, 0.36, d * 1.04), alpha)
	end
	local function DrawWound(alpha)
		local sh = Shoulder()
		local out = top.CFrame.UpVector
		Put(wound, CFrame.lookAt(sh, sh + out) * CFrame.Angles(0, PI / 2, 0), Vector3.new(0.06, w * 0.85, d * 0.85), alpha)
	end

	-- Antecipação: braço recua, ombro "abre"
	SetVis(orig, 1)
	local dir0 = (target - Shoulder()).Unit
	Burst(ctx, Shoulder(), 10)
	Animate(ctx, 0.16, function(p)
		local back = -0.5 * outCubic(p)
		local sh = Shoulder()
		DrawArm(sh + dir0 * back, (target - sh).Unit, 0, 1 - 0.1 * p, 0)
		DrawWound(0.1)
	end)

	-- Lançamento: arco leve, rotação e fibras se esticando
	local dist = (target - Shoulder()).Magnitude
	local fly = math.clamp(dist / 95, 0.18, 0.45)
	local startSh = Shoulder()
	local armBase
	Animate(ctx, fly, function(p)
		local sh = Shoulder()
		local k = outCubic(p)
		local endPos = target - (target - sh).Unit * L
		armBase = (startSh - dir0 * 0.5):Lerp(endPos, k) + Vector3.new(0, dist * 0.06 * bell(p), 0)
		local dir = (target - armBase).Unit
		DrawArm(armBase, dir, (1 - k) * 9, 1 + 0.12 * bell(p), 0)
		DrawWound(0.1)
		local pts = DrawTendons(T, sh, armBase, 0.2 * (1 - k), lerp(0.45, 0.15, k), 0.13, 0.05)
		if #pts > 0 and math.random() < 0.6 then
			local pt = pts[math.random(1, #pts)]
			Drop(ctx, pt, Vector3.new(rand(-3, 3), rand(1, 5), rand(-3, 3)))
		end
	end)

	-- Ancoragem: impacto, achatamento, aderência
	Burst(ctx, target, 16)
	Shake(hum, 0.2, 0.2)
	for _ = 1, 6 do Drop(ctx, target + normal * 0.2, normal * rand(3, 7) + Vector3.new(rand(-3, 3), rand(0, 4), rand(-3, 3))) end
	local gripCF = CFrame.lookAt(target + normal * 0.03, target + normal * 2) * CFrame.Angles(0, PI / 2, 0)
	Animate(ctx, 0.14, function(p)
		local sh = Shoulder()
		local dir = (target - sh).Unit
		armBase = target - dir * L * (1 - 0.12 * bell(p))
		DrawArm(armBase, dir, 0, 1 - 0.12 * bell(p), 0)
		DrawWound(0.1)
		local gd = lerp(0.3, w * 2.2, outBack(p))
		Put(grip, gripCF, Vector3.new(0.05, gd, gd), 0.1)
		DrawTendons(T, sh, armBase, 0.05, 0.12, 0.12, 0.05)
	end)

	-- Puxão: aceleração, desaceleração e balanço; fibras se contraem
	hum.PlatformStand = true
	local att = ctx.maid:Add(Instance.new("Attachment"))
	att.Parent = root
	local lv = ctx.maid:Add(Instance.new("LinearVelocity"))
	lv.Attachment0, lv.RelativeTo = att, Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e6
	lv.Parent = root
	local ao = ctx.maid:Add(Instance.new("AlignOrientation"))
	ao.Mode, ao.Attachment0, ao.Responsiveness, ao.MaxTorque = Enum.OrientationAlignmentMode.OneAttachment, att, 18, 1e6
	ao.Parent = root
	local dest = target + normal * 2.6
	local dist0 = (dest - root.Position).Magnitude
	local pullDir = (dest - root.Position).Unit
	Animate(ctx, 3, function(p, e)
		local toDest = dest - root.Position
		local dd = toDest.Magnitude
		local q = clamp01(1 - dd / math.max(dist0, 0.1))
		if dd < 3.2 or e > 2.8 then return end
		local speed = CFG.GrappleSpeed * smooth(0, 0.22, q) * (0.3 + 0.7 * (1 - smooth(0.7, 1, q)))
		speed = math.max(speed, 14)
		local side = pullDir:Cross(Vector3.yAxis)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
		local sway = side * math.sin(e * 6) * 7 * bell(q) + Vector3.new(0, math.sin(e * 4) * 3 * bell(q), 0)
		lv.VectorVelocity = toDest.Unit * speed + sway
		local f = flat(toDest)
		ao.CFrame = CFrame.lookAt(Vector3.zero, f) * CFrame.Angles(-0.5 * bell(q), 0, math.sin(e * 6) * 0.25 * bell(q))
		local sh = Shoulder()
		DrawArm(armBase, (target - armBase).Unit, 0, 1, 0)
		DrawWound(0.1)
		DrawTendons(T, sh, armBase, 0.02, 0.06 + 0.08 * (1 - q), 0.11, 0.05)
		Put(grip, gripCF, Vector3.new(0.05, w * 2.2, w * 2.2), 0.1)
	end)
	-- encerra o Animate cedo assim que chegar: (condição acima faz frames vazios até 3s)
	lv:Destroy() ao:Destroy()
	hum.PlatformStand = false
	root.AssemblyLinearVelocity = pullDir * 14 + Vector3.new(0, 20, 0)

	-- Retorno do braço e reconexão
	local fromBase = armBase
	Animate(ctx, 0.32, function(p)
		local sh = Shoulder()
		local k = p * p * (3 - 2 * p)
		local dir = (sh - fromBase).Magnitude > 0.1 and (fromBase - sh).Unit or top.CFrame.UpVector * -1
		local b = fromBase:Lerp(sh, k)
		DrawArm(b, -top.CFrame.UpVector:Lerp(dir, 1 - k).Unit, k * 4, 1 - 0.1 * bell(p), 0)
		DrawTendons(T, sh, b, 0, 0.2 * bell(p), 0.11 * (1 - 0.6 * k), k * 0.9)
		Put(grip, gripCF, Vector3.new(0.05, w * 2.2 * (1 - k), w * 2.2 * (1 - k)), 0.1 + 0.9 * k)
		DrawWound(0.1)
	end)
	Burst(ctx, Shoulder(), 14)
	DrawTendons(T, Shoulder(), Shoulder(), 0, 0, 0, 1)
	grip.Transparency, wound.Transparency = 1, 1
	Animate(ctx, 0.18, function(p)
		SetVis(orig, 1 - p)
		fake.Transparency, hand.Transparency = p, p
	end)
	SetVis(orig, 0)
	return true
end

------------------------------------------------------------------ INTERFACE
local UI = { buttons = {} }
local DEFS = {
	{ id = "Jump", label = "JUMP", glyph = "▲", key = Enum.KeyCode.Q, color = Color3.fromRGB(240, 92, 80), pos = UDim2.new(1, -110, 1, -215) },
	{ id = "Noclip", label = "NOCLIP", glyph = "●", key = Enum.KeyCode.E, color = Color3.fromRGB(200, 30, 50), pos = UDim2.new(1, -205, 1, -130) },
	{ id = "Grapple", label = "GANCHO", glyph = "➤", key = Enum.KeyCode.R, color = Color3.fromRGB(255, 140, 100), pos = UDim2.new(1, -110, 1, -110) },
}
local function Tw(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local TryAbility -- adiante

function UI.Build()
	local old = player.PlayerGui:FindFirstChild("RegenMovesetUI")
	if old then old:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "RegenMovesetUI", false, false
	gui.Parent = player.PlayerGui
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local s = gui.AbsoluteSize
		if s.X > 0 then scale.Scale = math.clamp(math.min(s.X / 900, s.Y / 520), 0.75, 1.2) end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()

	UI.hint = Instance.new("TextLabel")
	UI.hint.AnchorPoint, UI.hint.Position, UI.hint.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 60), UDim2.fromOffset(320, 34)
	UI.hint.BackgroundColor3, UI.hint.BackgroundTransparency = Color3.fromRGB(20, 18, 24), 0.2
	UI.hint.TextColor3, UI.hint.Font, UI.hint.TextSize = Color3.new(1, 1, 1), Enum.Font.GothamBold, 16
	UI.hint.Text, UI.hint.Visible = "TOQUE NA SUPERFÍCIE PARA LANÇAR", false
	UI.hint.Parent = gui
	Instance.new("UICorner", UI.hint).CornerRadius = UDim.new(0, 10)

	for _, def in ipairs(DEFS) do
		local b = Instance.new("TextButton")
		b.Name, b.Text, b.AutoButtonColor = def.id, "", false
		b.AnchorPoint, b.Position, b.Size = Vector2.new(0.5, 0.5), def.pos, UDim2.fromOffset(82, 82)
		b.BackgroundColor3, b.ClipsDescendants = Color3.fromRGB(22, 18, 26), true
		b.Parent = gui
		Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness, stroke.Color, stroke.ApplyStrokeMode = 2.5, def.color, Enum.ApplyStrokeMode.Border
		stroke.Parent = b
		local press = Instance.new("UIScale")
		press.Parent = b
		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency, icon.Size, icon.Position = 1, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 10)
		icon.Text, icon.Font, icon.TextSize, icon.TextColor3, icon.ZIndex = def.glyph, Enum.Font.GothamBlack, 32, def.color, 2
		icon.Parent = b
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency, label.Size, label.Position = 1, UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 1, -28)
		label.Text, label.Font, label.TextSize, label.TextColor3, label.ZIndex = def.label, Enum.Font.GothamBold, 12, Color3.new(1, 1, 1), 2
		label.Parent = b
		local cd = Instance.new("Frame")
		cd.AnchorPoint, cd.Position, cd.Size = Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0)
		cd.BackgroundColor3, cd.BackgroundTransparency, cd.BorderSizePixel, cd.ZIndex = Color3.new(0, 0, 0), 0.35, 0, 3
		cd.Parent = b
		local cdText = Instance.new("TextLabel")
		cdText.BackgroundTransparency, cdText.Size, cdText.ZIndex = 1, UDim2.fromScale(1, 1), 4
		cdText.Font, cdText.TextSize, cdText.TextColor3, cdText.Text = Enum.Font.GothamBlack, 22, Color3.new(1, 1, 1), ""
		cdText.Parent = b

		local btn = { def = def, b = b, stroke = stroke, press = press, icon = icon, cd = cd, cdText = cdText }
		UI.buttons[def.id] = btn
		b.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
				Tw(press, 0.07, { Scale = 0.88 })
			end
		end)
		local function rel() Tw(press, 0.35, { Scale = 1 }, Enum.EasingStyle.Back) end
		b.InputEnded:Connect(rel)
		b.MouseLeave:Connect(rel)
		b.Activated:Connect(function() TryAbility(def.id) end)
	end
end

function UI.Deny(id)
	local btn = UI.buttons[id]
	if not btn then return end
	local p = btn.def.pos
	task.spawn(function()
		for i = 1, 6 do
			btn.b.Position = p + UDim2.fromOffset((i % 2 == 0 and 1 or -1) * (7 - i), 0)
			task.wait(0.03)
		end
		btn.b.Position = p
	end)
end

function UI.Flash(id)
	local btn = UI.buttons[id]
	local ring = Instance.new("Frame")
	ring.AnchorPoint, ring.Position, ring.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.2, 0.2)
	ring.BackgroundColor3, ring.BackgroundTransparency, ring.ZIndex = btn.def.color, 0.3, 5
	ring.Parent = btn.b
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	Tw(ring, 0.4, { Size = UDim2.fromScale(1.6, 1.6), BackgroundTransparency = 1 })
	Debris:AddItem(ring, 0.45)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(now * 8)
	for id, btn in pairs(UI.buttons) do
		local left = (S.cd[id] or 0) - now
		local frac = clamp01(left / CFG.Cooldown[id])
		btn.cd.Size = UDim2.fromScale(1, frac)
		btn.cdText.Text = left > 0 and string.format("%.1f", left) or ""
		local locked = S.busy ~= nil and S.busy ~= id
		btn.b.BackgroundTransparency = locked and 0.55 or 0
		btn.icon.TextTransparency = locked and 0.6 or 0
		if S.busy == id then
			btn.stroke.Color = btn.def.color:Lerp(Color3.new(1, 1, 1), pulse * 0.6)
			btn.stroke.Thickness = 2.5 + pulse * 2
		else
			btn.stroke.Color = locked and Color3.fromRGB(90, 85, 100) or btn.def.color
			btn.stroke.Thickness = 2.5
		end
	end
end)

------------------------------------------------------------------ CONTROLE
local ABILITIES = { Jump = AbilityJump, Noclip = AbilityNoclip, Grapple = AbilityGrapple }

TryAbility = function(id)
	if S.busy == "Grapple" and id == "Grapple" and aimRequest then
		aimRequest = nil -- cancelar mira
		S.cancelAim = true
		return
	end
	if S.busy or os.clock() < (S.cd[id] or 0) or not alive(S.gen) then
		UI.Deny(id)
		return
	end
	if id == "Jump" and S.hum.FloorMaterial == Enum.Material.Air then UI.Deny(id) return end
	S.busy = id
	S.cancelAim = false
	UI.Flash(id)
	local ctx = NewCtx(S.gen)
	task.spawn(function()
		local ok, res = pcall(ABILITIES[id], ctx, function(on) UI.hint.Visible = on end)
		ctx.maid:Clean()
		if not ok and res ~= "CANCEL" then warn("[Regen] " .. id .. ": " .. tostring(res)) end
		-- gancho sem alvo válido não gasta recarga
		if not (id == "Grapple" and ok and res == false) then
			S.cd[id] = os.clock() + CFG.Cooldown[id]
		end
		S.busy = nil
	end)
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if aimRequest and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		aimRequest(Vector2.new(input.Position.X, input.Position.Y))
		return
	end
	for _, def in ipairs(DEFS) do
		if input.KeyCode == def.key then TryAbility(def.id) end
	end
end)

local function OnCharacter(char)
	S.gen += 1
	S.char = char
	S.hum = char:WaitForChild("Humanoid")
	S.root = char:WaitForChild("HumanoidRootPart")
	S.r6 = S.hum.RigType == Enum.HumanoidRigType.R6
	if not S.r6 then char:WaitForChild("RightHand", 5) char:WaitForChild("LeftFoot", 5) end
end

UI.Build()
if player.Character then task.spawn(OnCharacter, player.Character) end
player.CharacterAdded:Connect(OnCharacter)
