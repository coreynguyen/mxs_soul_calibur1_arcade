
/*               Maxscript: Soul Calibur for Arcade
   
   --------------------------------------------------------------
   Written By: mariokart64n
   Date      : January 8 2023
   Credits   : spaztron64, Spicyjpeg
   
   spaztron64:
	   https://github.com/spaztron64
       https://twitter.com/spaztron64
	
   Spicyjpeg:
       https://github.com/spicyjpeg
   --------------------------------------------------------------
   
   Notes     :
	Was contacted by spaztron64 on Jan4/2023 to look at
	SC1(Arcade). They provided samples and information through
	a blog post they made:
	https://lainnet.superglobalmegacorp.com/blog/2022_12_28_n01.html
   
	The post shared observations of the file format and geometry
	manipulations made in game by changing values in memory.
	
	I never played Arcade or Playstation games in my youth so
	naturally never looked at such formats in the past.
	
	That being said my understanding of these PS1 formats is
	extremely limited.
	
	Here is a block out of the various structures within the
	model file format
	     
	     [HEADER]
	         |
	         +-->[TABLE1]----------+    :: Strip Table
	         |       |             |
	         |       +-->[TABLE2]  |    :: Vertex Data
	         |                     |
	         +-->[TABLE3]          |    :: Geometry Data
	         |                     |
 	         +-->[TABLE4]<---------+    :: Bone Index / Name
	
	Strip Table, works more like a vertex group in blender,
	therefore each entry is actually a bone transform 
	accompanied by a pointer that goes to table2 (Vertex Data)
	containing vertices which that bone affects.
	
	I initially named it the strip table because in addition
	the vertices are interweaved or presented in strips.
	I'm still not sure why they are doing this, I would have
	to imagine it's for each sub material.
	
	Vertex Data in table2 are in local space so need to be
	transformed into world space using the transform provided
	in the entries of table1.
	
	Table3 contain entries for each face, and a bunch of junk
	that is important for the PlayStation grapics renderer.
	
	It annoyingly presents alot of packed commands which are
	essential for decoding the face indices.
	
	Table4 is a list of names which table1 points to, seems 
	not important for the model
	
   Changelog :
   [2022-01-10]
	spaztron64 pointed out where the 4th face index was, so
	now faces work. UV and weight support has been added.
	
	having some issues with bone rotations still, and normals.
	

	
*/ --------------------------------------------------------------
gc()
clearListener()
try(DestroyDialog sc1mesh)catch(sc1mesh)
rollout sc1mesh "SC1 Mesh" (
	local msh_index = 0
	local grp_index = 0
	
	struct fmtSC1Mesh_Table4 ( -- 32 Bytes
		/*
			list may or may not be at the end of the file?
			maybe its not even apart of the model file???
		*/
		/*uint16_t*/  	index = 0,
		/*char[30]*/  	name = "",
		fn read &f = (
			index = readShort f #unsigned
			
			-- Read the string portion, check for inconsistencies 
			local str_len = 30
			local result = true
			local pos = ftell f
			local i = 1, j = 1, b = 1
			name = ""
			for i = 1 to str_len do (
				b = readByte f #unsigned
				if b > 31 and b < 128 then (name += bit.IntAsChar(b))
				else if b == 0 and i < str_len then (
					for j = 1 to (str_len - i) do (
						b = readByte f #unsigned
						if b != 0 do (result = false)
						)
					exit
					)
				)
			fseek f (pos + str_len) #seek_set
			result
			)
		
		)
	
	struct fmtSC1Mesh_Table3 ( -- 28 Bytes (GPU Render Polygon Commands)
		/*
			
			the length of the table on the player characters is 28 bytes
			however on weapons this appear to be 24 bytes in length
			
			in accordance with this document;
				https://problemkaputt.de/psx-spx.htm#gpurenderpolygoncommands
			
			it may be that the meaning of this table changes based on the given
			GP0 command. 
			
		*/
		/*uint32_t*/  	GP0_ID = 0,
		/*
			12345678901234567890123456789012
			00000000011111111112222222222333
			--------------------------------
			00100000000000000000000000000000  // 0=3 poly , 1=4 poly ???
		*/
		/*uint32_t*/  	vertex1 = 0,
		/*uint32_t*/  	resev0 = 0,
		/*uint32_t*/  	resev1 = 0,
		/*uint32_t*/  	resev2 = 0,
		/*uint32_t*/  	resev3 = 0,
		/*uint32_t*/  	resev4 = 0,
		
		fn decode32_10_10_10_2 vertInt = (
			/*
				decode function from Spicyjpeg
				
				uVar10 is a 32 bit value that contains 3 indices
				bits 0-9 are the index of the first vertex, 10-19 of the second and 20-29 of the third
				
				function readFace uVar10 param_3:0
				local iVar7 = (bit.and uVar10 0x3ff) * 8 + param_3
				local gte_ldSXY0 = iVar7
				local gte_ldSXY1 = ((bit.and (bit.shift uVar10 -7) 0x1ff8) + param_3)
				local gte_ldSXY2 = ((bit.and (bit.shift uVar10 -0x11) 0x1ff8) + param_3)
				[gte_ldSXY0, gte_ldSXY1, gte_ldSXY2]
			*/
			local faceA = bit.and vertInt 0x000003FF
			local faceB = bit.shift (bit.and vertInt 0x000FFC00) -10
			local faceC = bit.shift (bit.and vertInt 0x3FF00000) -20
			local flag = bit.shift (bit.and vertInt 0xC0000000) -30
			#(faceA, faceB, faceC, flag)
			),
		
		fn getFaces use9bit:false = (
			local faces = #()
			local num_sides = 1
			if bit.get GP0_ID 28 do (
				num_sides = 2
				)
			if use9bit then (
				local tmp = decode32_10_10_10_2(vertex1)
				faces = #(tmp[1], tmp[2], tmp[3])
				if num_sides > 1 do (append faces (bit.and GP0_ID 0xFFFF))
				)
			else (
				local j = 1
				faces = for j = 0 to (num_sides + 1) collect (
					bit.shift (bit.and vertex1 (bit.shift 0xFF (j * 8))) -(j * 8)
					)
				)
			faces
			),
		
		fn getUvCoord = (
			local tvertArray = #(
				[bit.and resev2 0xFF, 255.0 - (bit.shift (bit.and resev2 0xFF00) -8), 0.0] / 255.0,
				[bit.and resev3 0xFF, 255.0 - (bit.shift (bit.and resev3 0xFF00) -8), 0.0] / 255.0,
				[bit.and resev4 0xFF, 255.0 - (bit.shift (bit.and resev4 0xFF00) -8), 0.0] / 255.0,
				[bit.and (bit.shift resev4 -16) 0xFF, 255.0 - (bit.shift resev4 -24), 0.0] / 255.0
				)
			if bit.get GP0_ID 28 == false do (deleteItem tvertArray 4)
			tvertArray
			),
		
		fn read &f size = (
			local result = false
			--local p = ftell f
			GP0_ID = readlong f #unsigned
			if GP0_ID != 0 do (
				vertex1 = readlong f #unsigned
				resev0 = readlong f #unsigned
				if size == 28 do (resev1 = readlong f #unsigned)
				resev2 = readlong f #unsigned
				resev3 = readlong f #unsigned
				resev4 = readlong f #unsigned
				result = true
				)
			--fseek f (p + size) #seek_set
			result
			)
		)
	
	struct fmtSC1Mesh_Table1 ( -- 32 Bytes
		/*
			I'm having issues reading the rotations,
			positions seem ok though...
			
			In Martin Korth's PSX document they state to
			read read 10 bits
			
			However I didn't implement this since positions are fine
			
			Martin Korth:
			Vertex (Parameter for Polygon, Line, Rectangle commands)
			  0-10   X-coordinate (signed, -1024..+1023)
			  11-15  Not used (usually sign-extension, but ignored by hardware)
			  16-26  Y-coordinate (signed, -1024..+1023)
			  26-31  Not used (usually sign-extension, but ignored by hardware)
			Size Restriction: The maximum distance between two vertices is 1023 horizontally,
			and 511 vertically. Polygons and lines that are exceeding that dimensions are NOT rendered.
			For example, a line from Y1=-300 to Y2=+300 is NOT rendered, a line from Y1=-100 to Y2=+400 is
			rendered (as far as it is within the drawing area).
			If portions of the polygon/line/rectangle are located outside of the drawing area,
			then the hardware renders only the portion that is inside of the drawing area.
			Unknown if the hardware is skipping all clipped pixels at once
			(within a single clock cycle), or if it's (slowly) processing them pixel by pixel?
			
			
		*/
		/*uint8_t*/   	bone_id0 = 0, -- on weapons this is NULL?
		/*uint8_t*/   	bone_id1 = 0,
		/*uint16_t*/  	unk011 = 0,
		/*uint32_t*/  	vert_addr = 0,
		/*uint32_t*/  	bone_addr = 0,
		/*uint16_t*/  	vert_count = 0,
		/*uint16_t*/  	norm_count = 0,
		/*int16_t*/   	rot_x = 0,
		/*int16_t*/   	rot_y = 0,
		/*int16_t*/   	rot_z = 0,
		/*int16_t*/   	unk017 = 0, -- Type of Bone Controller?
		/*int16_t*/   	pos_x = 0,
		/*int16_t*/   	pos_y = 0,
		/*int16_t*/   	pos_z = 0,
		/*int16_t*/   	parent = 0,
		
		fn read &f = (
			bone_id0 = readByte f #unsigned
			bone_id1 = readByte f #unsigned
			unk011 = readShort f #unsigned
			vert_addr = readLong f #unsigned
			bone_addr = readLong f #unsigned
			vert_count = readShort f #unsigned
			norm_count = readShort f #unsigned
			rot_x = readShort f #signed
			rot_y = readShort f #signed
			rot_z = readShort f #signed
			unk017 = readShort f #signed
			pos_x = readShort f #signed
			pos_y = readShort f #signed
			pos_z = readShort f #signed
			parent = readShort f #signed
			
			)
		)
	
	struct fmtSC1Mesh_Vertex ( -- 8 Bytes
		/*uint16_t[3]*/	vertex = [0, 0, 0],
		/*uint8_t*/   	index = 0,
		/*uint8_t*/   	flag = 0, -- 0x00 = Read Positions, 0x03 = Store Normals, 0x05 = Store Position
		/*
			there can be set commands within the vertices
			seems it appears when index is -1 or 0 and the 
			X Y Z is equal to 0
		*/
		fn isCmdPresent = ((index == 0 or index == 255) and vertex[1] == 0 and vertex[2] == 0 and vertex[3] == 0),
		fn read &f = (
			vertex = [readShort f #signed, readShort f #signed, readShort f #signed]
			index = readByte f #unsigned
			flag = readByte f #unsigned
			),
		fn getIndex = (bit.and (index + (bit.shift (bit.and flag 0x0F) 8)) 0x3FF)
		)
	
	struct fmtSC1Mesh_Strip ( -- n * 8 bytes
		/*
			this is a vertex buffer which table1 points to.
			I had assumed that they were stacking Vertex data in
			any order due to the commands.
			
			however it may actually be that they interlace the vertex
			positions, then the normals every time in that order
		*/
		
		/*Vertex[]*/	position = #(),
		/*Vertex[]*/	normal = #(),
		
		fn genFaces count = (
			/*
				generates crap face indices, just for debugging pruposes
			*/
			local faceArray = #()
			local i = 4
			local face = [1, 2, 3]
			while face[1] < count and face[2] < count and face[3] < count do (
				append faceArray face
				face = [face[1], face[3], i]
				i += 2
				)
			faceArray
			),
		
		fn build autoFaces:true = (
			/*
				this is just for debugging
			*/
			local count = position.count
			if count > 0 do (
				local msh
				local i = 1
				local vertArray = #()
				local faceArray = #()
				local hasCMD = false
				local vert_type = 0
				for i = 1 to count do (
					
					hasCMD = position[i].isCmdPresent()
					
					if hasCMD or i == count then (
						vert_type = position[i].flag
						if not hasCMD and i == count do (append vertArray position[i].vertex)
						faceArray = #()
						if autoFaces do (faceArray = genFaces(vertArray.count))
						msh = mesh vertices:vertArray faces:faceArray
						msh.name = "Object" + (msh_index as string) + " Group:" + (grp_index as string) + " Flag:" + (vert_type as string)
						msh_index += 1
						
						vertArray = #()
						) else (append vertArray position[i].vertex)
					)
				)
			
			),
		
		fn read &f &size &vert_count &norm_count = (
			grp_index += 1 -- for debugging
			/*
				Size of the vertex buffer is calculated from the
				addresses from table1 as a overrun safety
				
				vertex count and normal count is how
				many vertices to read respectively
				
			*/
			local p = ftell f
			local i = 1
			position = #()
			normal = #()
			if vert_count > 0 and (vert_count * 8) <= size then (
				position[vert_count] = fmtSC1Mesh_Vertex()
				for i = 1 to vert_count do (
					position[i] = fmtSC1Mesh_Vertex()
					position[i].read(f)
					)
				) else (format "ERROR: \tBuffer overrun on vertices\n")
			if norm_count > 0 and ((vert_count + norm_count) * 8) <= size then (
				normal[norm_count] = fmtSC1Mesh_Vertex()
				for i = 1 to norm_count do (
					normal[i] = fmtSC1Mesh_Vertex()
					normal[i].read(f)
					)
				) else (format "ERROR: \tBuffer overrun on normals\n")
			
			--build()
			fseek f (p + ((vert_count + norm_count) * 8)) #seek_set
			)
		)
	
	struct fmtSC1Mesh ( -- 32 + n bytes
		/*uint8_t*/   	unk001 = 0,
		/*uint8_t*/   	unk002 = 0,
		/*uint8_t*/   	unk003 = 0,
		/*uint8_t*/   	unk004 = 0,
		/*char[18]*/   	name = "",
		/*uint8_t*/   	unk005 = 0,
		/*uint8_t*/   	chr_index = 0,
		/*uint32_t*/  	table3_addr = 0,
		/*uint16_t*/  	table1_count = 0, -- this may be junk, as table looks like a fixed count
		/*uint16_t*/  	unk007 = 0,
		/*Table1[n]*/ 	table1 = #(), 
		/*Vertex[18]*/ 	table2 = #(), --  Vertex Strips?
		/*Table3[n]*/ 	table3 = #(), --  Geometry Commands?
		/*Table4[n]*/ 	table4 = #(), --  Bone Info?
		
		
		fn validate &f = (
			/*
				check that the file haeder is valid
			*/
			
			local result = true
			local pos = ftell f
			local i = 1
			local b = 0
			local str_len = 19
			
			-- Check the String only contains ANSI characters
			fseek f (pos + 4) #seek_set
			for i = 1 to 18 do (
				b = readByte f #unsigned
				if b > 0 and (b > 127 or b < 32) do (
					result = false
					exit
					)
				)
			
			-- Return
			fseek f pos #seek_set
			result
			),
		
		fn read &f byPassValidation:true = (
			
			if validate(f) or byPassValidation then (
				local pos = ftell f
				unk001 = readByte f #unsigned
				unk002 = readByte f #unsigned
				unk003 = readByte f #unsigned
				unk004 = readByte f #unsigned
				name = ""
				local i = 1
				for i = 1 to 18 do (name += bit.IntAsChar(readByte f #unsigned))
				unk005 = readByte f #unsigned
				chr_index = readByte f #unsigned
				table3_addr = readLong f #unsigned
				table1_count = readShort f #unsigned
				unk007 = readShort f #unsigned
				
				table1 = #()
				
				if table1_count > 0 then (
					table1[table1_count] = fmtSC1Mesh_Table1()
					
					local c = 0
					for i = 1 to table1_count do (
						table1[i] = fmtSC1Mesh_Table1()
						table1[i].read(f)
						)
					
					-- get file size
					local p = ftell f
					fseek f 0 #seek_end
					local fsize = ftell f
					
					
					-- if table3_addr larger then 1MB, possible that file is from a memory dump
					if table3_addr > 1000000 or table3_addr < 0 do (
						if table3_addr < 0 do (
							/*
								maxscript problem, int's are stored as a signed int (32bit)
								and its messing up my math, so just discard a few bits
							*/
							table3_addr = bit.and table3_addr 0xFFFFFF
							for i = 1 to table1.count do (table1[i].vert_addr = bit.and table1[i].vert_addr 0xFFFFFF)
							)
						
						-- goto end of table1
						fseek f (pos + ((table1_count + 1) * 0x20)) #seek_set
						
						-- skip past any padding
						local noPad = false
						while ftell f < fsize do (
							p = ftell f
							noPad = false
							for i = 1 to 8 do (if (readLong f #unsigned) != 0 do (noPad = true))
							
							if noPad do (
								fseek f p #seek_set
								exit
								)
							)
						
						-- get the nearest pointer from table1
						local nearest_addr = table3_addr -- default to the largest address
						for i = 1 to table1.count do (
							if table1[i].vert_addr > 0 and table1[i].vert_addr < nearest_addr do (
								nearest_addr = table1[i].vert_addr
								)
							)
						
						-- use nearest address to correct the rest of the addresses
						local addr_diff = nearest_addr - p
						table3_addr -= addr_diff
						for i = 1 to table1.count do (table1[i].vert_addr -= addr_diff)
						)
					
					
					
					local sizes = #(table3_addr, fsize)
					for i = 1 to table1_count do (
						if table1[i].vert_addr > 0 do (
							appendIfUnique sizes table1[i].vert_addr
							)
						)
					sort sizes
					fseek f p #seek_set
					local size = 0
					local x = 0
					local table2_count = 0
					
					grp_index = 0
					table2 = #()
					table2[table1_count] = fmtSC1Mesh_Strip()
					for i = 1 to table1_count do (
						table2[i] = fmtSC1Mesh_Strip()
						
						if table1[i].vert_addr > 0 do (
							size = 0
							x = findItem sizes table1[i].vert_addr
							
							size = sizes[x + 1] - sizes[x]
							table2[i] = #()
							if size > 0 do (
								fseek f table1[i].vert_addr #seek_set
								table2[i] = fmtSC1Mesh_Strip()
								table2[i].read f size table1[i].vert_count table1[i].norm_count
								)
							)
						grp_index += 1
						)
					
					fseek f table3_addr #seek_set
					table3 = #()
					local table3_size = 28
					if chr_index == 0 do (table3_size = 24)
					local t = fmtSC1Mesh_Table3()
					while ftell f < fsize do (
						t = fmtSC1Mesh_Table3()
						if not (t.read f table3_size) do (exit)
						append table3 t
						)
					
					
					/*
						table4 seems out of place, we need to be careful reading it
					*/
					table4 = #()
					p = ftell f
					if p < fsize then (
						
						-- arg sometimes theres padding here
						i = 1
						while ftell f < fsize and i < 16 do (
							if (readByte f #unsigned) > 0 do (
								fseek f -1 #seek_cur
								exit
								)
							)
						
						
						-- try to calculate potential table4 count from remain file size
						local table4_count = ((fsize - (ftell f)) / 32.0) as integer
						local b = fmtSC1Mesh_Table4()
						if table4_count > 0 do (
							i = 1
							while ftell f < fsize and i <= table4_count do (
								p = ftell f
								b = fmtSC1Mesh_Table4()
								if not b.read(f) then (
									format "Failed to Complete Reading of Bone % {%}\n" i (p as integer)
									exit
									) else (append table4 b)
								i += 1
								)
							)
						) else (format "Failed to Read Table4 {%}\n" ((ftell f) as integer))
					
					format "\n\n__________________________________________\n \tParsing Completed at {%}\n\n" ((ftell f) as integer)
					) else (format "ERROR: \tNo Table Entries {%}\n" table1_count)
				) else (format "ERROR: \tInvalid File Header\n")
			),
		
		fn manualBoneFixes &boneTrans = (
			format "(%)\n" name
			local i = 1
			local num_bones = boneTrans.count
			local pos = [0.0, 0.0, 0.0]
			local tfm = matrix3 1
			for i = 1 to num_bones do (
				tfm = boneTrans[i]
				pos = boneTrans[i].row4
				case i of (
					 1: tfm *= rotateYPRMatrix 0 90 0    -- Torso
					 4: tfm *= rotateYPRMatrix 180 0 180 -- right shoulder
					 5: tfm *= rotateYPRMatrix 0 0 335   -- right arm
					 7: tfm *= rotateYPRMatrix 90 180 90 -- right wrist
					 9: tfm *= rotateYPRMatrix 180 0 335 -- left arm
					11: tfm *= rotateYPRMatrix 90 180 90 -- left wrist
					12: tfm *= rotateYPRMatrix 180 270 0 -- hips
					)
				tfm.row4 = pos
				boneTrans[i] = tfm
				)
			),
		
		fn intToBin n = (
			local s = ""
			local i = 1
			for i = 1 to 32 do (if bit.get n i then s += "0" else s += "1")
			s
			),
		
		fn build debugFaces:false debugTVerts:false transformVerts:true transformCorrections:true buildSkeleton:true impNormals:false importWeights:true = (
			
			-- Convert Bones from Local to World Space
			local i = 1
			local tfm = matrix3 1
			local boneTrans = #()
			local num_bones = table1.count
			local rot = [0.0, 0.0, 0.0]
			for i = 1 to num_bones do (
				rot = ([table1[i].rot_x, table1[i].rot_y, table1[i].rot_z] / 4096.0 * 360.0)
				tfm = rotateYPRMatrix rot[1] rot[2] rot[3]
				tfm.row4 = [table1[i].pos_x, table1[i].pos_y, table1[i].pos_z]
				append boneTrans tfm
				)
			if chr_index > 0 and transformCorrections do (manualBoneFixes(&boneTrans))
			for i = 1 to num_bones do (
				if table1[i].parent > -1 and table1[i].parent != i - 1 do (
					boneTrans[i] *= boneTrans[table1[i].parent + 1]
					)
				)
			
			
			-- Decode Faces
			local f = 1, s = 1, x = 1, j = 1
			local num_faces = table3.count
			local num_sides = 3 -- triangles, or quads
			local polyType = 0
			local max_index = 0
			local face = [1, 1, 1]
			local faceArray = #()
			local faceArray_Debug = #()
			local faceArray_Debug2 = #()
			local tvertArray = #()
			local texCoord = #()
			
			for f = 1 to num_faces do (
				texCoord = table3[f].getUvCoord use9bit:(chr_index > 0)
				faces = table3[f].getFaces use9bit:(chr_index > 0)
				num_sides = 0
				if faces.count > 2 do (num_sides = faces.count - 2)
				for s = 1 to num_sides do (
					face = [faces[s], faces[s + 2], faces[s + 1]] + 1 -- get First 3
					if bit.and s 1 == 1 do (face = [face[1], face[3], face[2]]) -- get second 3
					for j = 1 to 3 do (if face[j] > max_index do (max_index = face[j]))
					append faceArray face
						
					if bit.and s 1 == 1 then (
						append tvertArray texCoord[0 + s]
						append tvertArray texCoord[1 + s]
						append tvertArray texCoord[2 + s]
						)
					else (
						append tvertArray texCoord[0 + s]
						append tvertArray texCoord[2 + s]
						append tvertArray texCoord[1 + s]
						)
					
					
					
					
					
					if debugFaces do (
						append faceArray_Debug table3[f].GP0_ID
						append faceArray_Debug2 f
						)
					)
				)
			
			-- Create Vertex Arrays
			local vertArray = #()
			local normArray = #()
			local boneids = #()
			local vertCounts = #() -- to generate material boundries
			if max_index > 0 do (
				max_index += 1
				vertCounts[num_bones] = 0
				vertArray[max_index] = [0.0, 0.0, 0.0]
				if impNormals do (normArray[max_index] = [0.0, 1.0, 0.0])
				--format "max_index: \t%\n" max_index
				boneids[max_index] = #()
				for i = 1 to max_index do (
					vertArray[i] = [0.0, 0.0, 0.0]
					if impNormals do (normArray[i] = [0.0, 1.0, 0.0])
					boneids[i] = #()
					)
				local v = 1
				local num_verts = 0
				local num_norms = 0
				local vert_off = 1
				local vert_pos = 1
				
				for i = 1 to num_bones do (
					num_verts = table2[i].position.count
					max_index = 0
					for v = 1 to num_verts do (
						if (table2[i].position[v].isCmdPresent()) then (
							if table2[i].position[v].flag == 0 do (vert_off += num_verts)
							)
						else (
							vert_pos = table2[i].position[v].getIndex() + vert_off
							if vert_pos > max_index do max_index = vert_pos
							while vert_pos > vertArray.count do (
								append vertArray [0.0, 0.0, 0.0]
								append boneids[i] (#())
								)
							if transformVerts then (
								tfm = transMatrix table2[i].position[v].vertex
								if boneTrans.count > 0 do (tfm *= boneTrans[i])
								vertArray[vert_pos] += tfm.row4
								) else (vertArray[vert_pos] = table2[i].position[v].vertex)
							while vert_pos > boneids.count do (
								max_index+=1
								append boneids (#())
								)
							append boneids[vert_pos] i
							)
						)
					vertCounts[i] = max_index - 1
					)
				if impNormals do (
					vert_off = 1
					for i = 1 to num_bones do (
						num_norms = table2[i].normal.count
						format "num_norms: \t%\n" num_norms
						for v = 1 to num_norms do (
							if (table2[i].normal[v].isCmdPresent()) then (
								if table2[i].normal[v].flag == 0 do (vert_off += num_norms)
								)
							else (
								vert_pos = table2[i].normal[v].getIndex() + vert_off
								--if vert_pos > max_index do max_index = vert_pos
								while vert_pos > normArray.count do (
									append normArray [0.0, 1.0, 0.0]
									)
								tfm = transMatrix table2[i].normal[v].vertex
								if boneTrans.count > 0 do (tfm *= boneTrans[i])
								normArray[vert_pos] += tfm.row4
								)
							)
						)
					)
				)
			
			-- Push Geometry to the 3D scene
			max modify mode
			local boneArray = #()
			local bn = undefined
			if buildSkeleton or importWeights do (
				for i = 1 to num_bones do (
					bn = Dummy()
					bn.wirecolor = yellow
					bn.transform = boneTrans[i]
					append boneArray bn
					)
				for i = 1 to num_bones do (
					boneArray[i].showLinks = boneArray[i].showLinksOnly = true
					if table1[i].parent > -1 and table1[i].parent != i - 1 do (
						boneArray[i].parent = boneArray[table1[i].parent + 1]
						)
					)
				)
			local weights = #()
			local num_verts = vertArray.count
			if num_verts > 0 do (
				if transformVerts do (
					weights[num_verts] = 1.0
					local num_weights = 0
					for i = 1 to num_verts do (
						weights[i] = 1.0
						num_weights = boneids[i].count
						--print num_weights
						if num_weights > 0 do (
							weights[i] = 1.0 / num_weights
							vertArray[i] /= num_weights
							)
						)
					)
				local msh = undefined
				if debugFaces then (
					for i = 1 to faceArray.count do (
						
						msh = mesh vertices:vertArray faces:#(faceArray[i])
						msh.name = "FACE " + (i as string) + " (" + (faceArray_Debug2[i] as string) + ") 0x" + (bit.IntAsHex faceArray_Debug[i]) + " [" + (intToBin faceArray_Debug[i]) + "]"
						
						
						
						
						)
					)
				else (
					
					-- Try to generate material boundries
					local matArray = #()
					--print vertCounts
					if faceArray.count > 0 do (
						local x = 1
						local matid = 1
						local mtotal = 0
						matArray[faceArray.count] = 0
						for f = 1 to faceArray.count do (
							x = 1
							mtotal = 0
							while x <= vertCounts.count do (
								if mtotal < faceArray[f][1] and mtotal < faceArray[f][2] and mtotal < faceArray[f][3] then (matid = x) else (exit)
								mtotal += vertCounts[x]
								x += 1
								)
							matArray[f] = matid
							)
						)
					
					
					with redraw off (
						if debugTVerts then (
							msh = mesh vertices:tvertArray faces:(for i = 1 to tvertArray.count / 3 collect [((i - 1) * 3) + 1, ((i - 1) * 3) + 2, ((i - 1) * 3) + 3]) materialIDs:matArray tverts:tvertArray
							)
						else (
							msh = mesh vertices:vertArray faces:faceArray materialIDs:matArray tverts:tvertArray
							)
						buildTVFaces msh
						for i = 1 to tvertArray.count / 3 do (setTVFace msh i [((i - 1) * 3) + 1, ((i - 1) * 3) + 2, ((i - 1) * 3) + 3])
						msh.backfacecull = on
						msh.displayByLayer = false
						msh.wirecolor = random (color 0 0 0) (color 255 255 255)
						for i = 1 to msh.numfaces do setFaceSmoothGroup msh i 1
						
						select msh
						modPanel.addModToSelection (smooth ()) ui:off
						msh.modifiers[#Smooth].autosmooth = on
						maxOps.CollapseNodeTo msh 1 true
						
						if vertCounts.count > 0 do (
							msh.material = MultiMaterial numSubs:vertCounts.count
							for i = 1 to vertCounts.count do (
								msh.material[i] = StandardMaterial()
								msh.material[i].diffuse = random white black
								)
							)
						if impNormals do (
							-- doesnt work, maybe the game uses a different set of indices???
							local normID = #{}
							local normMod = Edit_Normals()
							addmodifier msh normMod ui:off
							normMod.selectBy = 1
							normMod.displayLength = 0.25
							for i = 1 to normArray.count do (
								normID = #{}
								normMod.ConvertVertexSelection #{i} &normID
								for j in normID do (normMod.SetNormal j (normalize normArray[i]))
								normID = undefined
								)
							--collapseStack submesh
							subobjectLevel = 0
							)
						if importWeights and transformVerts do (
							
							local skinMod = undefined, num_bones = 0, boneMap = #()
							local numBones = 0, bone_index = 1, bi = #(), bw = #()
							local bonePal = #(), bneTmp = #()
							
							-- apply a skin modifier
							skinMod = skin()
							addModifier msh skinMod ui:off
							
							-- generate weight pallete by collect bones being used in weight data
							for i = 1 to num_verts do (
								for j = 1 to boneids[i].count do (
									if findItem bonePal boneids[i][j] == 0 do (
										append bonePal boneids[i][j]
										)
									)
								)
							
							-- assign bones to skin modifier, from the weight pallete
							for i = 1 to bonePal.count do (
								skinOps.addbone skinMod boneArray[bonePal[i]]  (
									if i == bonePal.count then 1 else 0
									)
								)
							
							
							-- create a bonemap
							if boneArray.count > 0 do (
								-- get names of bones in skin list
								bneTmp[bonePal.count] = ""
								for i = 1 to bonePal.count do (
									bneTmp[i] = skinOps.GetBoneName skinMod i 0
									)
								-- map boneArray to skin list
								boneMap[boneArray.count] = 1
								for i = 1 to boneArray.count do (
									boneMap[i] = 1 -- default assignment to first bone in skin list
									bone_index = findItem bneTmp boneArray[i].name
									if bone_index > 0 do (boneMap[i] = bone_index)
									)
								)
							
							-- apply weights to skin modifier
							modPanel.setCurrentObject skinMod
							for i = 1 to num_verts do (
								numBones = boneids[i].count
								bi = #()
								bw = #()
								if numBones > 0 then (
									bi[numBones] = 0
									bw[numBones] = 0.0
									for j = 1 to numBones do (
										bi[j] = boneMap[boneids[i][j]]
										bw[j] = weights[i]
										)
									)
								else (
									bi = #(1)
									bw = #(1.0)
									)
								skinOps.ReplaceVertexWeights skinMod i bi bw
								)
							
							if skinOps.isWeightToolOpen skinMod == 0 do (
								skinOps.WeightTool skinMod
								)
							skinMod.filter_vertices = on
							)
						
						)
					
					)
				)
			
			
			
			
			)
		)
	
	button btn "Import Model" width:120 height:30
	checkBox chk_clear "Clear Scene on Import" checked:true
	checkBox chk_skin "Weights" checked:false
	checkBox chk_bskl "Skeleton" checked:false
	group "Debug Options" (
		checkBox chk_dface "Individual Faces" checked:false
		checkBox chk_tvert "Build UV Mesh" checked:false
		checkBox chk_notrans "Disable Transforms" checked:false
		checkBox chk_notransfix "Disable Transforms Fixes" checked:false
		checkBox chk_normls "Apply Normals" checked:false
		)
	label lbl1 "Written By: mariokart64n" align:#left
	label lbl2 "Date: Jan 10, 2023" align:#left
	
	local m = fmtSC1Mesh()
	fn read file clear_scene:true = (
		if file != undefined and file != "" do (
			local f = try(fopen file "rb")catch(undefined)
			if f != undefined then (
				clearListener()
				print file
				if chk_clear.checked do delete $*
				m = fmtSC1Mesh()
				m.read(f)
				m.build debugFaces:chk_dface.checked debugTVerts:chk_tvert.checked transformCorrections:(not chk_notransfix.checked) transformVerts:(not chk_notrans.checked) buildSkeleton:chk_bskl.checked impNormals:chk_normls.checked importWeights:chk_skin.checked
				--m.build debugFaces:false buildSkeleton:false importWeights:false
				fclose f
				) else (format "failed to open file {%}\n" file)
			)
		)
	
	on btn pressed do (read(filen = GetOpenFileName caption:"Select a File" types: "SC1 (Arcade) Model (*.bin)|*.BIN|All files (*.*)|*.*|"))
	)

CreateDialog sc1mesh
/*
delete $*
sc1mesh.read (
	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\Y106tes.dat" -- RAM DUMP
	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\xianghua1P_decompressed_fromROM.bin"
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\xianghua1P_sword_decompressed.bin"
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\0 001_tang_mitu-MODE ARTHOR.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\0MITURUGI_c-KATANA_T.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\1 003_Texture1-MODEL TAKI.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\SE2-NINTOU_1_1.7-0.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\2 SE2-MODEL_MAN_3.4- VOLDO.dat" -- RAM DUMP (CRASHES)
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\BUKI_M1-KATAL_T_M_.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\3 006-MODEL_MAN.40-0 SOPHITUA.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\8majyo_saiban-006KE.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\4 012b-MODEL_MAN_1_1 ASTAROTH.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\astaroth2p_decompressed_rom.bin"
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\8As_Ono-012_buki.8-0.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\5 00b_foreign-00B_1_ IVY.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\00b_BUKI-BUKI.10-0.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\6 007_tang_geek-MODE NIGHTMARE.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\nightmare1P_sword_decompressed.bin"
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\7 Kl1p_f2-MODEL_00.1 KILIK.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\00c_BUKI-konbou5x8.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\8 Mks1p_g-MODEL_MAN  MAXI.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\00c_BUKI-konbou5x8.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\9 Fan1p_f-MODEL_MAN  HWANG.dat" -- RAM DUMP
-- 	"E:\\BackUp\\MyCloud4100\\Coding\\Maxscripts\\File IO\\Soul Calibur 1 (Arcade)\\Samples\\hwang1P_sword_decompressed.bin"
-- 	"C:\\Users\\Corey\\Downloads\\mame0250b_64bit\\dump1.CEM"
	)
*/