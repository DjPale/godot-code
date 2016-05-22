tool
extends Reference
const FORMAT_TMX = 0
const FORMAT_JSON = 1

var metaFilePath = null
var tileset = TileSet.new()
var textureMap = {}
var layers = []

func _getParentDir(path):
	var fileName = path.substr(0, path.find_last("/"))
	return fileName

func _getFileName(path):
	var fileName = path.substr(path.find_last("/")+1, path.length() - path.find_last("/")-1)
	var dotPos = fileName.find_last(".")
	if dotPos != -1:
		fileName = fileName.substr(0,dotPos)
	return fileName

func _pathJoin(base, path):
	var p = base + "/" + path
	p = p.replace("//", "/")
	var nodes = p.split("/")
	var tmp = []
	for n in nodes:
		if n == "..":
			tmp.pop_back()
		elif n.length()>0 and n!=".":
			tmp.push_back(n)
	var res = ""
	if base.begins_with("/"):
		res += "/"
	for i in range(tmp.size()):
		res += tmp[i]
		if i < tmp.size()-1:
			res += "/"
	return res

func _exportDictionary(d):
	var res = ""
	for k in d:
		var type = null
		var value = d[k]
		k = k.replace(" ", "")
		if typeof(k) == TYPE_BOOL:
			type = "bool"
		elif typeof(k) == TYPE_REAL:
			type = "float"
		elif typeof(k) == TYPE_INT:
			type = "float"
		else:
			type = "String"
			value = str("\"", value, "\"")
		res += str("export(", type,") var ", k, " = ", value, "\n")
	return res


func loadFromFile(path):
	var meta = null
	var file = File.new()
	file.open(path, File.READ)
	if file.is_open():
		metaFilePath = path
		var fileContent = file.get_as_text()
		meta = _parse(fileContent, FORMAT_TMX)
	file.close()
	return (meta != null)

func _parse(fileContent, format):
	var meta = null
	if format == FORMAT_TMX:
		meta = _parseXMLContent(fileContent)
	if meta != null:
		tileset.clear()
		textureMap.clear()
		layers = []
		var metaDir = _getParentDir(metaFilePath)
		var tileCount = 0
		# Create tileset
		for ts in meta["tilesets"]:
			for t in ts["tiles"]:
				var texturePath = _pathJoin(metaDir, t["source"])
				if not textureMap.has(texturePath):
					textureMap[texturePath] = load(texturePath)
				var id = t["id"]
				tileset.create_tile(id)
				tileset.tile_set_texture(id, textureMap[texturePath])
				tileset.tile_set_region(id, Rect2(t["posX"],t["posY"], t["width"],t["height"]))
				tileset.tile_set_name(id, str("Tile", id))
				tileCount += 1
		# Create layers
		for l in meta["layers"]:
			var layer = TileMap.new()
			layer.set_name(l["name"])
			layer.set_pos(Vector2(l["offsetx"], l["offsety"]))
			layer.set_opacity(l["opacity"])
			layer.set_hidden(!l["visible"])
			layer.set_cell_size(Vector2(meta["tilewidth"], meta["tileheight"]))
			var scriptSource = "tool\nextends TileMap\n\n"
			scriptSource += _exportDictionary(l["properties"])
			var script = GDScript.new()
			script.set_source_code(scriptSource)
			layer.set_script(script)
			var mode = TileMap.MODE_SQUARE
			if meta["orientation"] == "isometric":
				mode = TileMap.MODE_ISOMETRIC
			layer.set_mode(mode)
			layer.set_tileset(tileset)

			var gidata = l["data"]["content"]
			for y in range(l["height"]):
				for x in range(l["width"]):
					layer.set_cell(x, y, gidata[y * l["width"] + x])
			layers.append(layer)

	return meta

func save(path):
	for k in textureMap:
		ResourceSaver.save(str(path,"/",_getFileName(k),".tex"), textureMap[k])
	# Save tileset
	ResourceSaver.save(str(path,"/", "tilesets" ,".res"), tileset)
	# Save layers
	var packer = PackedScene.new()
	var node = Node2D.new()
	for l in layers:
		node.add_child(l)
		l.set_owner(node)
	packer.pack(node)
	ResourceSaver.save(str(path,"/", "tilemap",".tscn"), packer)

################################## XML Parser ##################################

func _parseXMLContent(xmlContent):
	var parser = XMLParser.new()
	var meta = null
	if OK == parser.open_buffer(xmlContent.to_utf8()):
		var err = parser.read()
		if err == OK:
			meta = {}
			meta["tilesets"] = []
			meta["layers"] = []
			var iterated = false
			while(err != ERR_FILE_EOF):
				iterated = false
				if parser.get_node_type() == parser.NODE_ELEMENT:
					if "map" == parser.get_node_name():
						meta["version"] = _xmlNodeAttrValue(parser, "version", "1.0")
						meta["orientation"] = _xmlNodeAttrValue(parser, "orientation", "orthogonal")
						meta["renderorder"] = _xmlNodeAttrValue(parser, "renderorder", "right-down")
						meta["width"] = _xmlNodeAttrValue(parser, "width", 0)
						meta["height"] = _xmlNodeAttrValue(parser, "height", 0)
						meta["tilewidth"] = _xmlNodeAttrValue(parser, "tilewidth", 0)
						meta["tileheight"] = _xmlNodeAttrValue(parser, "tileheight", 0)
						meta["nextobjectid"] = _xmlNodeAttrValue(parser, "nextobjectid", 0)

					# tilesets
					elif "tileset" == parser.get_node_name():
						var tileset = {}
						tileset["firstgid"] = _xmlNodeAttrValue(parser, "firstgid", 1)
						tileset["name"] = _xmlNodeAttrValue(parser, "name", "tileset")
						tileset["tilecount"] = _xmlNodeAttrValue(parser, "tilecount", 0)
						tileset["columns"] = _xmlNodeAttrValue(parser, "columns", 0)
						tileset["tilewidth"] = _xmlNodeAttrValue(parser, "tilewidth", 0)
						tileset["tileheight"] = _xmlNodeAttrValue(parser, "tileheight", 0)
						tileset["spacing"] = _xmlNodeAttrValue(parser, "spacing", 0)
						tileset["margin"] = _xmlNodeAttrValue(parser, "margin", 0)
						tileset["tiles"] = []
						while(parser.read() != ERR_FILE_EOF):
							if parser.get_node_type() == parser.NODE_ELEMENT:
								if "tile" == parser.get_node_name():
									var tile = {}
									tile["id"] = tileset["firstgid"] + _xmlNodeAttrValue(parser, "id", 1)
									# image under title
									while(parser.read() != ERR_FILE_EOF):
										if parser.get_node_type() == parser.NODE_ELEMENT:
											if "image" == parser.get_node_name():
												tile["posX"] = 0
												tile["posY"] = 0
												tile["width"] = _xmlNodeAttrValue(parser, "width", 0)
												tile["height"] = _xmlNodeAttrValue(parser, "height", 0)
												tile["source"] = _xmlNodeAttrValue(parser, "source", "")
												tile["trans"] = _xmlNodeAttrValue(parser, "trans", Color(1,1,1,1))
												break
									tileset["tiles"].append(tile)
									continue
								if "image" == parser.get_node_name():
									for i in range(tileset["tilecount"]):
										var tile = {}
										tile["id"] = tileset["firstgid"] + i
										if  tileset["columns"] == 0:
											tile["posX"] = tileset["spacing"]
											tile["posY"] = i * tileset["tileheight"] + (i+1) * tileset["margin"]
										else:
											var column = (i%tileset["columns"])
											var row = (i/tileset["columns"])
											tile["posX"] = column * tileset["tilewidth"] + (column+1) * tileset["spacing"]
											tile["posY"] = row * tileset["tileheight"] +  (row+1) * tileset["margin"]
										tile["width"] = tileset["tilewidth"]
										tile["height"] = tileset["tileheight"]
										tile["source"] = _xmlNodeAttrValue(parser, "source", "")
										tile["trans"] = _xmlNodeAttrValue(parser, "trans", Color(1,1,1,1))
										tileset["tiles"].append(tile)
									# Never change the indent below!
									break
								elif "tileset" == parser.get_node_name():
									iterated = true
									break
						meta["tilesets"].append(tileset)
					if iterated:
						continue
					# layers
					elif "layer" == parser.get_node_name():
						var layer = {}
						layer["name"] = _xmlNodeAttrValue(parser, "name", "Unnamed")
						layer["width"] = _xmlNodeAttrValue(parser, "width", 0)
						layer["height"] = _xmlNodeAttrValue(parser, "height", 0)
						layer["visible"] = _xmlNodeAttrValue(parser, "visible", true)
						layer["opacity"] = _xmlNodeAttrValue(parser, "opacity", 1.0)
						layer["offsetx"] = _xmlNodeAttrValue(parser, "offsetx", 0.0)
						layer["offsety"] = _xmlNodeAttrValue(parser, "offsety", 0.0)
						layer["properties"] = {}
						while(parser.read() != ERR_FILE_EOF):
							if parser.get_node_type() == parser.NODE_ELEMENT:
								if "properties" == parser.get_node_name():
									while(parser.read() != ERR_FILE_EOF):
										if parser.get_node_type() == parser.NODE_ELEMENT:
											if "property" == parser.get_node_name():
												var type = _xmlNodeAttrValue(parser, "type", "string")
												var name = _xmlNodeAttrValue(parser, "name", "unnamed")
												var value = _xmlNodeAttrValue(parser, "value", "0")
												if type == "int":
													value = int(value)
												elif type == "float":
													value = float(value)
												elif type == "bool":
													value = bool(value)
												layer["properties"][name] = value
											else:
												break
								if "data" == parser.get_node_name():
									var data = {}
									data["encoding"] = _xmlNodeAttrValue(parser, "encoding", "csv")
									var content = ""
									if parser.read() != ERR_FILE_EOF and parser.get_node_type() == parser.NODE_TEXT:
										content = parser.get_node_data()
									data["content"] = _parseCSVData(content)
									layer["data"] = data
									break
						meta["layers"].append(layer)
				# iterater current element
				err = parser.read()
	return meta

func _parseCSVData(rawStr):
	var array = IntArray()
	var rows = rawStr.split("\n")
	for row in rows:
		var gids = row.split(",")
		for gid in gids:
			if gid and gid.length() > 0:
				array.push_back(int(gid))
	return array

func _xmlNodeAttrValue(parser, attName, defaultV):
	var res = defaultV
	if parser and parser.has_attribute(attName):
		res = parser.get_named_attribute_value(attName)
	var tarType = typeof(defaultV)
	if typeof(res) != tarType:
		if tarType == TYPE_INT:
			res = int(res)
		elif tarType == TYPE_BOOL:
			res = bool(res)
		elif tarType == TYPE_REAL:
			res = float(res)
		elif tarType == TYPE_COLOR:
			res = Color(res)
	return res
