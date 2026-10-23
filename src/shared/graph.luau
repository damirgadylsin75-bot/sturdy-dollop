-- Street-graph helpers shared by the server simulation and the client snapping.

local Graph = {}

function Graph.edgeKey(a, b)
	if a < b then
		return tostring(a) .. "_" .. tostring(b)
	end
	return tostring(b) .. "_" .. tostring(a)
end

function Graph.nearestNode(city, pos)
	local best, bestD = nil, math.huge
	for _, node in pairs(city.nodes) do
		local d = (node.pos - pos).Magnitude
		if d < bestD then
			best, bestD = node.id, d
		end
	end
	return best, bestD
end

function Graph.nearestNodeWithin(city, pos, maxDist)
	local best, bestD = nil, math.huge
	for _, node in pairs(city.nodes) do
		local d = (node.pos - pos).Magnitude
		if d < bestD then
			best, bestD = node.id, d
		end
	end
	if bestD <= maxDist then
		return best, bestD
	end
	return nil
end

-- Returns: point (Vector2 on the edge), edge, distance.
function Graph.nearestEdgePoint(city, pos)
	local bestPoint, bestEdge, bestDist = nil, nil, math.huge
	for _, e in ipairs(city.edges) do
		local pa = city.nodes[e.a].pos
		local pb = city.nodes[e.b].pos
		local ab = pb - pa
		local lenSq = ab:Dot(ab)
		local t = 0
		if lenSq > 0 then
			t = math.clamp((pos - pa):Dot(ab) / lenSq, 0, 1)
		end
		local p = pa:Lerp(pb, t)
		local d = (p - pos).Magnitude
		if d < bestDist then
			bestPoint, bestEdge, bestDist = p, e, d
		end
	end
	return bestPoint, bestEdge, bestDist
end

-- Dijkstra over the street graph.
-- sources: array of node ids.
-- edgeCost(edge, fromId) -> number (optional; default = geometric length).
-- Returns dist: { [nodeId] = number }.
function Graph.dijkstra(city, sources, edgeCost)
	local dist = {}
	for id in pairs(city.nodes) do
		dist[id] = math.huge
	end
	local visited = {}
	local queue = {}
	for _, s in ipairs(sources) do
		dist[s] = 0
		queue[#queue + 1] = s
	end
	while #queue > 0 do
		-- pick the closest queued node (the graph is tiny, linear scan is fine)
		local bi, bd = nil, math.huge
		for k, id in ipairs(queue) do
			local d = dist[id]
			if d < bd then
				bi, bd = k, d
			end
		end
		local current = queue[bi]
		queue[bi] = queue[#queue]
		queue[#queue] = nil
		if not visited[current] then
			visited[current] = true
			local node = city.nodes[current]
			for _, nb in ipairs(node.edges) do
				if not visited[nb] then
					local w
					if edgeCost then
						w = edgeCost(city.edgeIndex[Graph.edgeKey(current, nb)], current)
					else
						w = (node.pos - city.nodes[nb].pos).Magnitude
					end
					local nd = bd + w
					if nd < dist[nb] then
						dist[nb] = nd
						queue[#queue + 1] = nb
					end
				end
			end
		end
	end
	return dist
end

return Graph
