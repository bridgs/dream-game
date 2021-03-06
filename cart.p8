pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[

render layers:
	2:	plots/grass
	3:	troops
	5:	buildings, players, ball
	7:	effects
	8:	menus
	9:	ui

platform channels:
	1:	level bounds
	2:	commander

hurt channels:
	1:	buildings

]]

-- convenient no-op function that does nothing
function noop() end

local controllers={1,0}
local level_bounds={
	top={x=0,y=32,vx=0,vy=0,width=128,height=0,platform_channel=1},
	left={x=0,y=0,vx=0,vy=0,width=0,height=128,platform_channel=1,is_left_wall=true},
	bottom={x=0,y=105,vx=0,vy=0,width=128,height=0,platform_channel=1},
	right={x=127,y=0,vx=0,vy=0,width=0,height=128,platform_channel=1,is_right_wall=true}
}

local game_frames
local freeze_frames
local screen_shake_frames

local entities
local commanders
local ball
local game_end_screen
local buttons={{},{}}
local button_presses={{},{}}

local entity_classes={
	commander={
		width=2,
		height=15,
		mana_regen_rate=1,
		collision_indent=0.5,
		move_y=0,
		platform_channel=2,
		is_commander=true,
		-- is_frozen=false,
		move_speed=1,
		ball_speed=1,
		troop_move_speed=1,
		bonus_troops_per_keep=0,
		aftertouch_frames=0,
		troop_damage_mult=1,
		ball_damage_mult=1,
		init=function(self)
			spawn_entity("spark_explosion",self:center_x(),self:center_y(),{
				color=self.colors[2],
				speed=4,
				num_sparks=30,
				variation=0.5,
				frames_to_death=30
			})
			local props={commander=self}
			self.health=spawn_entity("health_counter",ternary(self.is_facing_left,100,10),4,props)
			self.gold=spawn_entity("gold_counter",ternary(self.is_facing_left,75,11),116,props)
			self.xp=spawn_entity("xp_counter",ternary(self.is_facing_left,101,37),116,props)
			self.plots=spawn_entity("plots",ternary(self.is_facing_left,76,20),36,props)
			self.army=spawn_entity("army",0,0,props)
			local x=ternary(self.is_facing_left,92,24)
			self.primary_menu=spawn_entity("menu",x,63,{
				commander=self,
				menu_items={{1,"build"},{2,"upgrade"}},--,{3,"cast spell"}},
				on_select=function(self,item,index)
					-- build
					if index==1 then
						self.commander.build_menu:show()
					-- upgrade
					elseif index==2 then
						local location_menu=self.commander.location_menu
						location_menu.action="upgrade"
						location_menu.prev_choice=item
						location_menu:show(mid(1,flr(#location_menu.menu_items*(self.commander:center_y()-20)/75),#location_menu.menu_items))
					-- cast spell
					elseif index==3 then
						self.commander.spell_menu:show()
					end
					return true
				end
			})
			self.spell_menu=spawn_entity("menu",x,63,{
				commander=self,
				menu_items={},
				on_select=function(self,item,index)
					local commander=self.commander
					local mana=commander.mana
					if mana.amount>=mana.max_amount then
						if item[2]=="fireball" then
							spawn_entity("fireball",commander:center_x()-4,commander:center_y()-5,{
								vx=commander.facing_dir
							})
							self.commander.is_frozen=false
							mana.amount=0
							mana.displayed_amount=0
						elseif item[2]=="plenty" then
							local location_menu=self.commander.location_menu
							location_menu.action="plenty"
							location_menu.prev_choice=item
							location_menu:show(mid(1,flr(#location_menu.menu_items*(self.commander:center_y()-20)/75),#location_menu.menu_items))
						elseif item[2]=="bolt" then
							self.commander.is_frozen=false
							local opponent=commanders[self.commander.opposing_player_num]
							spawn_entity("bolt",ternary(opponent.is_facing_left,100,10),0)
							sfx(27)
							opponent.health:add(-5)
							mana.amount=0
							mana.displayed_amount=0
						end
						return true
					end
					sfx(12)
				end
			})
			if self.class_name=="witch" then
				self.mana=spawn_entity("mana_counter",ternary(self.is_facing_left,75,11),124,{
					commander=self
				})
			end
			self.build_menu=spawn_entity("menu",x,63,{
				commander=self,
				menu_items={{4,"keep","makes troops",100},{5,"farm","generates gold",100},{6,"inn","grants xp",100},{7,"archers","shoots enemies",100},{8,"church","heals wounds",100}},
				on_select=function(self,item,index)
					if item[4]<=self.commander.gold.amount then
						local location_menu=self.commander.location_menu
						location_menu.action="build"
						location_menu.prev_choice=item
						location_menu:show(mid(1,flr(#location_menu.menu_items*(self.commander:center_y()-20)/75),#location_menu.menu_items))
						return true
					end
					sfx(12)
				end
			})
			self.location_menu=spawn_entity("location_menu",x,63,{
				commander=self,
				menu_items=self.plots.locations,
				on_select=function(self,location)
					local commander=self.commander
					if self.action=="build" then
						if commander:build(self.prev_choice[2],self.prev_choice[4],location) then
							commander.is_frozen=false
							return true
						end
					elseif self.action=="upgrade" or self.action=="plenty" then
						if location.building and location.building.is_alive then
							if self.action=="plenty" then
								if commander.mana.amount>=commander.mana.max_amount then
									location.building.plenty_frames=600
									sfx(26)
									commander.mana.amount=0
									commander.mana.displayed_amount=0
									commander.is_frozen=false
									return true
								end
							elseif location.building.upgrades<2 and commander:upgrade(location.building) then
								commander.is_frozen=false
								return true
							end
						end
					end
					sfx(12)
				end
			})
		end,
		update=function(self)
			decrement_counter_prop(self,"aftertouch_frames")
			if self.mana and self.frames_alive%13==0 then
				self.mana:add(self.mana_regen_rate)
			end
			-- activate the menu
			if not self.is_frozen and button_presses[self.player_num][4] then
				self.is_frozen=true
				button_presses[self.player_num][4]=false
				self.primary_menu:show()
				sfx(13)
			end
			-- move vertically
			if self.is_frozen then
				self.move_y=0
			else
				self.move_y=ternary(buttons[self.player_num][3],1,0)-ternary(buttons[self.player_num][2],1,0)
			end
			self.vy=self.move_speed*self.move_y
			if self.vy!=0 and self.frames_alive%10==ternary(self.player_num==1,0,3) then
				sfx(7+self.player_num)
			end
			self:apply_velocity()
			if self.aftertouch and self.aftertouch_frames>0 and self.vy!=0 and ball then
				ball.vy+=ternary(self.vy>0,0.01,-0.01)
			end
			-- keep in bounds
			self.y=mid(level_bounds.top.y-5,self.y,level_bounds.bottom.y-self.height+5)
		end,
		draw=function(self)
			-- draw paddle
			rectfill(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,self.colors[1])
			line(self.x+ternary(self.is_facing_left,0.5,1.5),self.y+0.5,self.x+ternary(self.is_facing_left,0.5,1.5),self.y+self.height-1.5,self.colors[3])
			-- draw commander
			pal(11,self.colors[2])
			pal(8,self.colors[2])
			pal(12,self.colors[2])
			if self.move_y!=0 then
				palt(ternary(self.frames_alive%10<5,12,8),true)
			end
			draw_sprite(4*self.sprite,0,4,6,self.x+ternary(self.is_facing_left,4,-6),self.y-4+flr(self.height/2),self.is_facing_left)
		end,
		draw_shadow=function(self)
			-- draw commander shadow
			local x,y=self.x+ternary(self.is_facing_left,3.5,-5.5),self.y+0.5+flr(self.height/2)
			rectfill(x,y,x+3,y+1,1)
			-- draw paddle shadow
			rectfill(self.x-0.5,self.y+1.5,self.x+self.width-1.5,self.y+self.height+0.5,1)
		end,
		build=function(self,building_type,cost,location)
			if self.gold.amount>=cost then
				self.gold:add(-cost)
				if location.building and location.building.is_alive then
					location.building:die()
				end
				sfx(16)
				location.building=spawn_entity(building_type,location.x-1,location.y-1,{
					commander=self,
					battle_line=location.battle_line
				})
				if self.class_name=="knight" and self.xp.level>=2 then
					location.building.max_hit_points+=35
					location.building.hit_points+=35
				end
				return location.building
			end
		end,
		upgrade=function(self,building)
			local cost=building.upgrade_options[building.upgrades+1][3]
			if ((building.upgrades==0 and self.xp.level>=3) or (building.upgrades==1 and self.xp.level>=6)) and self.gold.amount>=cost then
				sfx(16)
				self.gold:add(-cost)
				building.upgrades+=1
				building.max_hit_points+=75
				building.hit_points+=75
				return true
			end
		end,
		on_level_up=noop
	},
	witch={
		extends="commander",
		colors={13,12,12,4,5},
		sprite=0,
		on_level_up=function(self,level)
			if level==2 then
				add(self.primary_menu.menu_items,{3,"cast spell"})
				add(self.spell_menu.menu_items,{9,"fireball","burns all"})
				return {"spell: fireball","burns all"}
			elseif level==4 then
				add(self.spell_menu.menu_items,{10,"plenty","double effects"})
				return {"spell: plenty","double effects"}
			elseif level==5 then
				self.inn_mana_generation=true
				return {"inns: produce","mana per hit"}
			elseif level==7 then
				add(self.spell_menu.menu_items,{13,"bolt","damage castle"})
				return {"spell: bolt","damage castle"}
			elseif level==8 then
				self.mana_regen_rate=3
				return {"triple mana","regeneration"}
			end
		end
	},
	thief={
		extends="commander",
		colors={9,10,10,4,4},
		sprite=1,
		on_level_up=function(self,level)
			if level==2 then
				self.move_speed=1.6
				self.ball_speed=1.4
				return {"+ball speed","+move speed"}
			elseif level==4 then
				self.stealing=true
				return {"steal gold per","damaged building"}
			elseif level==5 then
				self.aftertouch=true
				return {"aftertouch","ball trajectory"}
			elseif level==7 then
				self.trick_shot=true
				return {"automatic","trick shot"}
			elseif level==8 then
				self.double_triggers=true
				return {"your buildings","trigger twice"}
			end
		end
	},
	knight={
		extends="commander",
		colors={8,8,14,15,2},
		sprite=2,
		on_level_up=function(self,level)
			if level==2 then
				local location
				for location in all(self.plots.locations) do
					if location.building then
						location.building.max_hit_points+=35
						location.building.hit_points+=35
					end
				end
				return {"+building hp"}
			elseif level==4 then
				self.move_speed=0.65
				self.y-=5
				self.height+=10
				return {"+paddle size","-move speed"}
			elseif level==5 then
				self.troop_move_speed=1.75
				return {"+troop move","speed"}
			elseif level==7 then
				self.bonus_troops_per_keep=2
				return {"keeps: +2 troops","per hit"}
			elseif level==8 then
				self.troop_damage_mult=2
				self.ball_damage_mult=2
				return {"x2 troop damage","x2 ball damage"}
			end
		end
	},
	counter={
		render_layer=9,
		amount=0,
		displayed_amount=0,
		update=function(self)
			if self.displayed_amount<self.amount then
				self.displayed_amount=min(self.amount,self.displayed_amount+rnd_int(self.min_tick,self.max_tick))
			else
				self.displayed_amount=max(0,max(self.amount,self.displayed_amount-rnd_int(self.min_tick,self.max_tick)))
			end
		end,
		add=function(self,amount)
			self.amount=mid(0,self.amount+amount,self.max_amount)
			self:on_add(amount)
		end,
		on_add=noop
	},
	health_counter={
		extends="counter",
		amount=50,
		displayed_amount=50,
		max_amount=50,
		min_tick=1,
		max_tick=1,
		width=16,
		height=6,
		draw=function(self)
			draw_sprite(12,17,7,6,self.x,self.y)
			if self.displayed_amount<self.amount then
				color(11)
			elseif self.displayed_amount>self.amount then
				color(7)
			else
				color(8)
			end
			print(self.displayed_amount,self.x+9.5,self.y+1.5)
		end,
		on_add=function(self,amount)
			if amount<0 then
				spawn_entity("spark_explosion",self:center_x(),self:center_y(),{
					color=8,
					num_sparks=-amount,
					speed=3
				})
			end
		end
	},
	gold_counter={
		extends="counter",
		amount=100,
		max_amount=999,
		min_tick=9,
		max_tick=16,
		width=17,
		height=5,
		draw=function(self)
			draw_sprite(19,18,4,5,self.x,self.y)
			pset(self.x+21.5,self.y+2.5,5)
			if self.displayed_amount<self.amount then
				color(10)
			elseif self.displayed_amount>self.amount then
				color(8)
			else
				color(7)
			end
			print(self.displayed_amount,self.x+6.5,self.y+0.5)
		end
	},
	xp_counter={
		amount=0,
		max_amount=40,
		extends="counter",
		min_tick=2,
		max_tick=2,
		width=16,
		height=7,
		level=1,
		draw=function(self)
			draw_sprite(24,27,11,3,self.x,self.y+1)
			print(self.level,self.x+13.5,self.y+0.5,7)
			line(self.x+0.5,self.y+6.5,self.x+self.width-0.5,self.y+6.5,2)
			if self.amount>0 then
				line(self.x+0.5,self.y+6.5,self.x+0.5+(self.displayed_amount/self.max_amount)*(self.width-1),self.y+6.5,14)
			end
		end,
		on_add=function(self,amount)
			if self.level>=8 then
				self.amount=0
				self.displayed_amount=0
			elseif self.amount>=self.max_amount then
				self.amount=0
				self.displayed_amount=0
				self.max_amount+=12
				self.level+=1
				spawn_entity("spark_explosion",self:center_x(),self:center_y(),{
					color=14,
					num_sparks=10,
					speed=3
				})
				sfx(23)
				local text=self.commander:on_level_up(self.level) or {}
				if self.level==3 then
					text={"lvl 2 buildings","unlocked"}
				elseif self.level==6 then
					text={"lvl 3 buildings","unlocked"}
				end
				spawn_entity("level_up_effect",ternary(self.commander.is_facing_left,64,0),12,{
					commander=self.commander,
					line_1=text[1],
					line_2=text[2]
				})
			end
		end
	},
	mana_counter={
		amount=0,
		max_amount=42,
		extends="counter",
		min_tick=5,
		max_tick=5,
		width=42,
		height=3,
		level=1,
		draw=function(self)
			rectfill(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,1)
			if self.displayed_amount>0 then
				rectfill(self.x+0.5,self.y+0.5,self.x-0.5+self.displayed_amount,self.y+self.height-0.5,ternary(self.displayed_amount>=42 and self.frames_alive%30<15,7,12))
			end
		end,
	},
	level_up_effect={
		width=63,
		height=18,
		frames_to_death=200,
		draw=function(self)
			pal(3,self.commander.colors[5])
			pal(11,self.commander.colors[2])
			local dy=ternary(self.line_2,0,ternary(self.line_1,4,8))
			draw_sprite(45,27,46,6,self.x+9,self.y+dy)
			if self.line_1 then
				print(self.line_1,self.x+32.5-2*#self.line_1,self.y+7.5+dy,7)
			end
			if self.line_2 then
				print(self.line_2,self.x+32.5-2*#self.line_2,self.y+13.5+dy,7)
			end
		end
	},
	pop_text={
		render_layer=7,
		width=1,
		height=1,
		vy=-1.5,
		frames_to_death=32,
		update=function(self)
			self.vy+=0.1
			self:apply_velocity()
		end,
		draw=function(self)
			local text=""..self.amount
			local dx=0
			if self.type=="health" then
				draw_sprite(12,17,7,6,self.x-2*#text-5,self.y-6)
				color(8)
			elseif self.type=="xp" then
				dx=-7
				draw_sprite(35,27,7,4,self.x+2*#text-3,self.y-4)
				color(14)
			elseif self.type=="gold" then
				draw_sprite(19,18,4,5,self.x-2*#text-2,self.y-5)
				color(10)
			elseif self.type=="mana" then
				draw_sprite(91,25,4,5,self.x-2*#text-2,self.y-5)
				color(12)
			end
			print(text,self.x-2*#text+4.5+dx,self.y-4.5)
		end
	},
	plots={
		render_layer=2,
		width=31,
		height=65,
		init=function(self)
			local x,y=self.x,self.y
			self.locations={
				{x=x+13,y=y,battle_line=1},
				{x=x,y=y+13,battle_line=2},
				{x=x+26,y=y+17,battle_line=2},
				{x=x+13,y=y+30,battle_line=3},
				{x=x,y=y+43,battle_line=4},
				{x=x+26,y=y+47,battle_line=4},
				{x=x+13,y=y+60,battle_line=5}
			}
		end,
		draw=function(self)
			local loc
			for loc in all(self.locations) do
				-- draw_sprite(58,7,5,5,loc.x,loc.y)
				draw_sprite(16,15,3,2,loc.x+1,loc.y+1)
				-- pset(loc.x+2.5,loc.y+2.5,8)
			end
		end
	},
	army={
		render_layer=3,
		init=function(self)
			self.troops={}
		end,
		update=function(self)
			local commander=self.commander
			local troop
			for troop in all(self.troops) do
				if ball and ball.is_alive and ball.commander and ball.commander!=self.commander and contains_point(ball,troop.x,troop.y,1) then
					self:destroy_troop(troop)
				elseif (commander.is_facing_left and troop.x<=18) or (not commander.is_facing_left and troop.x>=108) then
					troop.y-=commander.troop_move_speed*0.1
					troop.battle_line=nil
					if troop.y<28 then
						commanders[ternary(commander.is_facing_left,1,2)].health:add(-1)
						freeze_and_shake_screen(0,5)
						self:destroy_troop(troop)
					end
				else
					troop.x+=commander.troop_move_speed*0.1*commander.facing_dir
					-- check for collisions with buildings
					local location
					for location in all(commanders[commander.opposing_player_num].plots.locations) do
						if location.building and location.building.is_alive and contains_point(location.building,troop.x,troop.y,1) then
							troop.x-=2*commander.facing_dir
							location.building:damage(commander.troop_damage_mult)
							troop.hits+=1
							if troop.hits>5 then
								self:destroy_troop(troop)
							end
							sfx(18)
						end
					end
				end
			end
		end,
		draw=function(self)
			local troop
			for troop in all(self.troops) do
				pset(troop.x+0.5,troop.y-0.5,self.commander.colors[4])
				pset(troop.x+0.5,troop.y+0.5,self.commander.colors[2])
			end
		end,
		draw_shadow=function(self)
			local troop
			for troop in all(self.troops) do
				pset(troop.x-0.5,troop.y+0.5,1)
			end
		end,
		spawn_troop=function(self,building)
			add(self.troops,{
				x=building.x+3+self.commander.facing_dir*(rnd(5)),
				y=building:center_y()+rnd_int(-4,3),
				battle_line=building.battle_line,
				hits=0
			})
		end,
		destroy_troop=function(self,troop)
			del(self.troops,troop)
			sfx(24)
			spawn_entity("spark_explosion",troop.x,troop.y,{
				color=self.commander.colors[2],
				min_angle=45,
				max_angle=135,
				num_sparks=1,
				speed=1.5
			})
		end
	},
	menu={
		render_layer=8,
		width=11,
		height=11,
		is_visible=false,
		highlighted_index=1,
		hint_counter=0,
		update=function(self)
			if self.is_visible then
				local player_num=self.commander.player_num
				increment_counter_prop(self,"hint_counter")
				if button_presses[player_num][2] then
					self.highlighted_index=ternary(self.highlighted_index==1,#self.menu_items,self.highlighted_index-1)
					self.hint_counter=0
					sfx(10)
				end
				if button_presses[player_num][3] then
					self.highlighted_index=self.highlighted_index%#self.menu_items+1
					self.hint_counter=0
					sfx(10)
				end
				if button_presses[player_num][4] then
					button_presses[player_num][4]=false
					if self:on_select(self.menu_items[self.highlighted_index],self.highlighted_index) then
						self:hide()
						sfx(11)
					end
				end
				if button_presses[player_num][5] then
					self:hide()
					self.commander.is_frozen=false
					sfx(14)
				end
			end
		end,
		draw=function(self)
			if self.is_visible then
				local y=self.y-5.5*#self.menu_items
				pal(1,0)
				pal(11,self.commander.colors[2])
				-- draw menu items
				local i
				for i=1,#self.menu_items do
					draw_sprite(0,6,11,12,self.x,y+10*i-4)
					draw_sprite(5+7*self.menu_items[i][1],0,7,7,self.x+2,y+10*i-2)
				end
				-- draw pointer
				self:render_pointer(self.x,y+10*self.highlighted_index-1,10)
				-- draw text box
				local curr_item=self.menu_items[self.highlighted_index]
				self:render_text(curr_item[2],curr_item[3],curr_item[4])
			end
		end,
		on_select=noop,
		show=function(self,starting_index)
			if not self.is_visible then
				self.is_visible=true
				self.highlighted_index=starting_index or 1
				self.hint_counter=0
			end
		end,
		hide=function(self)
			self.is_visible=false
		end,
		render_text=function(self,text,hint,gold)
			local x=ternary(self.commander.is_facing_left,64,1)
			draw_sprite(11,7,2,9,x,105)
			draw_sprite(13,7,1,9,x+2,105,false,false,58)
			draw_sprite(11,7,2,9,x+60,105,true)
			if hint and self.hint_counter%40>20 then
				print(hint,x+3.5,107.5,0)
			else
				print(text,x+3.5,107.5,0)
				if gold then
					print(gold,x+48.5,107+0.5,9)
				end
			end
		end,
		render_pointer=function(self,x,y,w)
			draw_sprite(16,7,13,8,x+ternary(self.commander.is_facing_left,(w or 0) + 2,-14),y,self.commander.is_facing_left)
		end
	},
	location_menu={
		extends="menu",
		draw=function(self)
			if self.is_visible then
				local commander=self.commander
				local prev_choice=self.prev_choice
				local loc=self.menu_items[self.highlighted_index]
				self:render_pointer(loc.x,loc.y,4)
				if self.action=="build" then
					self:render_text(prev_choice[2],prev_choice[3],prev_choice[4])
				elseif self.action=="upgrade" or self.action=="plenty" then
					local location=self.menu_items[self.highlighted_index]
					local building=location.building
					if building and building.is_alive then
						if self.action=="plenty" then
							self:render_text("double effect")
						elseif building.upgrades==0 and commander.xp.level<3 then
							self:render_text("requires lvl 3")
						elseif building.upgrades==1 and commander.xp.level<6 then
							self:render_text("requires lvl 6")
						else
							-- if building.upgrades==0 and commander.xp.level>2 or building.upgrades==
							local upgrade=building.upgrade_options[1+building.upgrades]
							self:render_text(upgrade[1],upgrade[2],upgrade[3])
						end
					else
						self:render_text("--")
					end
				end
			end
		end
	},
	ball={
		width=3,
		height=3,
		collision_indent=0.5,
		hit_channel=1, -- buildings
		collision_channel=1 + 2, -- level bounds + commanders
		ball_speed=1,
		init=function(self)
			self.frames_alive+=ternary(rnd()<0.5,20,0)
		end,
		update=function(self)
			if self.vx==0 and self.vy==0 and button_presses[1][0] and self.frames_alive>10 then
				sfx(3)
				local launch_to_player_1=(self.frames_alive%40<20)
				self.vx=ternary(launch_to_player_1,-0.65,0.65)
			end
			local prev_x=self.x
			self:apply_velocity(self.ball_speed)
			if self.commander and self.commander.trick_shot and (prev_x<63)!=(self.x<63) then
				self.vy*=-1
			end
			-- if ball.vx!=0 and ball.vy==0 then
			-- 	ball.vy=0.002
			-- end
		end,
		draw=function(self)
			if self.commander then
				color(self.commander.colors[3])
			else
				color(7)
			end
			rectfill(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5)
			if self.vx==0 and self.vy==0 then
				print("press",self.x-7.5,self.y+7.5+6,7)
				pal(1,0)
				draw_sprite(35,31,7,9,self.x-2,self.y+13+6)
				print("to launch",self.x-16.5,self.y+24.5+6,7)
				local launch_to_player_1=(self.frames_alive%40<20)
				pal(11,commanders[ternary(launch_to_player_1,1,2)].colors[2])
				draw_sprite(42,27,3,5,self.x+ternary(launch_to_player_1,-5,5),self.y-1,self.frames_alive%40<20)
			end
		end,
		draw_shadow=function(self)
			rectfill(self.x-0.5,self.y+1.5,self.x+self.width-1.5,self.y+self.height+0.5,1)
		end,
		on_collide=function(self,dir,other)
			if not other.is_commander or (not other.is_facing_left and dir=="left") or (other.is_facing_left and dir=="right") then
				self:handle_collision_position(dir,other)
				-- bounce!
				if (dir=="left" and self.vx<0) or (dir=="right" and self.vx>0) then
					self.vx*=-1
				elseif (dir=="up" and self.vy<0) or (dir=="down" and self.vy>0) then
					self.vy*=-1
				end
				-- take damage
				if other.is_left_wall or other.is_right_wall then
					local commander=commanders[ternary(other.is_left_wall,1,2)]
					local other_commander=commanders[ternary(other.is_left_wall,2,1)]
					commander.health:add(-15*other_commander.ball_damage_mult)
					freeze_and_shake_screen(0,5)
					self:die()
					sfx(6)
				-- commander can bounce the ball in interesting ways
				elseif other.is_commander then
					local offset_y=self:center_y()-other:center_y()+other.vy/2
					local max_offset=other.height/2
					local percent_offset=mid(-1,offset_y/max_offset,1)
					percent_offset*=abs(percent_offset)
					self.vy=1.2*percent_offset+0.4*other.vy
					other.gold:add(55)
					spawn_entity("pop_text",self:center_x(),other.y-5,{
						amount=55,
						type="gold"
					})
					other.xp:add(15)
					spawn_entity("pop_text",self:center_x(),other.y+1,{
						amount=15,
						type="xp"
					})
					self.commander=other
					self.vx+=ternary(self.vx<0,-1,1)*0.02
					self.ball_speed=other.ball_speed
					other.aftertouch_frames=50
					sfx(4)
				else
					sfx(5)
				end
				-- stop moving / colliding
				return true
			end
		end,
		on_death=function(self)
			ball=spawn_entity("ball",62,66)
		end
	},
	building={
		width=7,
		height=7,
		upgrades=0,
		offset_y=0,
		hit_points=100,
		max_hit_points=100,
		show_health_bar_frames=0,
		hurt_channel=1, -- buildings
		effect_offset=0,
		plenty_frames=0,
		update=function(self)
			decrement_counter_prop(self,"show_health_bar_frames")
			decrement_counter_prop(self,"plenty_frames")
		end,
		draw=function(self)
			pal(3,self.commander.colors[1])
			pal(11,self.commander.colors[2])
			pal(14,self.commander.colors[3])
			draw_sprite(0+8*self.upgrades,8+15*self.sprite,8,15,self.x,self.y-9+self.offset_y)
			if self.plenty_frames>0 then
				draw_sprite(42,33,8,5,self.x-1,self.y-5-self.health_bar_height[self.upgrades+1])
			end
			if self.show_health_bar_frames>0 then
				local height=self.health_bar_height[self.upgrades+1]
				rectfill(self.x+0.5,self.y-1.5-height,self.x+6.5,self.y-0.5-height,2)
				rectfill(self.x+0.5,self.y-1.5-height,self.x+0.5+6*self.hit_points/self.max_hit_points,self.y-0.5-height,8)
			end
		end,
		draw_shadow=function(self)
			draw_sprite(24,18+12*self.sprite+4*self.upgrades,11,4,self.x-9,self.y+2)
		end,
		on_hurt=function(self,other)
			self.invincibility_frames=15
			if other.class_name=="ball" then
				if other.commander==self.commander then
					self:on_trigger(other)
					if self.commander.double_triggers or self.plenty_frames>0 then
						self.effect_offset=7
						self:on_trigger(other)
						self.effect_offset=0
					end
					spawn_entity("trigger_effect",self.x,self.y,{
						color=self.commander.colors[2]
					})
				elseif other.commander then
					self:damage(other.commander.ball_damage_mult*20)
					if other.commander.stealing then
						self.commander.gold:add(-5)
						other.commander.gold:add(5)
						spawn_entity("pop_text",other.commander:center_x(),other.commander.y,{
							amount=5,
							type="gold"
						})
					end
					sfx(17)
				end
			else
				self:damage(other.damage)
				sfx(17)
			end
		end,
		damage=function(self,amount)
			self.hit_points-=amount
			self.show_health_bar_frames=60
			spawn_entity("spark_explosion",self:center_x(),self.y+self.height,{
				color=6,
				min_angle=70,
				max_angle=110,
				variation=0.2,
				gravity=0.15,
				speed=3.5,
				num_sparks=min(amount,5),
				frames_to_death=17
			})
			if amount>1 then
				freeze_and_shake_screen(0,2)
			end
			if self.hit_points<=0 then
				self:die()
			end
		end,
		on_death=function(self)
			sfx(28)
		end,
		on_trigger=noop
	},
	keep={
		extends="building",
		sprite=1,
		health_bar_height={4,6,7},
		upgrade_options={{"keep v2","+3 troop",150},{"keep v3","+7 troop",200},{"max upgrade"}},
		on_trigger=function(self)
			local num_troops=({1,3,7})[self.upgrades+1]+self.commander.bonus_troops_per_keep
			local i
			for i=1,num_troops do
				self.commander.army:spawn_troop(self)
			end
			sfx(19)
		end
	},
	farm={
		extends="building",
		sprite=2,
		health_bar_height={2,2,2},
		offset_y=4,
		upgrade_options={{"farm v2","+50 gold",150},{"farm v3","+75 gold",200},{"max upgrade"}},
		on_trigger=function(self,other)
			local gold=({25,50,75})[self.upgrades+1]
			self.commander.gold:add(gold)
			spawn_entity("pop_text",self:center_x(),other.y-5-self.effect_offset,{
				amount=gold,
				type="gold"
			})
			sfx(7)
		end
	},
	inn={
		extends="building",
		sprite=3,
		health_bar_height={3,4,5},
		upgrade_options={{"inn v2","+30 xp",150},{"inn v3","+50 xp",200},{"max upgrade"}},
		on_trigger=function(self,other)
			local xp=({10,20,35})[self.upgrades+1]
			self.commander.xp:add(xp)
			spawn_entity("pop_text",self:center_x()-ternary(self.commander.inn_mana_generation,7,0),other.y-5-self.effect_offset,{
				amount=xp,
				type="xp"
			})
			sfx(20)
			if self.commander.inn_mana_generation then
				local mana=self.commander.mana_regen_rate*({5,8,12})[self.upgrades+1]
				self.commander.mana:add(mana)
				spawn_entity("pop_text",self:center_x()+7,other.y-5-self.effect_offset,{
					amount=mana,
					type="mana"
				})
			end
		end
	},
	archers={
		extends="building",
		sprite=4,
		health_bar_height={4,6,8},
		upgrade_options={{"archers v2","wide range",150},{"archers v3","max range",200},{"max upgrade"}},
		on_trigger=function(self,other)
			local army=commanders[self.commander.opposing_player_num].army
			local troop
			local range=({13,21,27})[self.upgrades+1]
			local arrows=({3,6,9})[self.upgrades+1]
			for troop in all(army.troops) do
				local dx=mid(-100,self:center_x()-troop.x,100)
				local dy=mid(-100,self:center_y()-troop.y,100)
				if dx*dx+dy*dy<range*range and arrows>0 then
					army:destroy_troop(troop)
					arrows-=1
				end
			end
			-- local i
			for i=1,(5+2*self.upgrades) do
				local dist=(0.6+rnd(0.3))*range
				local angle=(i-rnd())/5
				spawn_entity("spark_explosion",self:center_x()+dist*cos(angle),self:center_y()+dist*sin(angle),{
					color=4,
					min_angle=60,
					max_angle=120,
					num_sparks=2,
					speed=1,
					frames_to_death=30,
					gravity=0.02,
					delay=i
				})
			end
			spawn_entity("range_indicator",self:center_x(),self:center_y(),{
				range=range,
				frames_to_death=30,
				color=8
			})
			sfx(21)
		end
	},
	range_indicator={
		render_layer=7,
		draw=function(self)
			circ(self.x+0.5,self.y+0.5,self.range,self.color)
		end
	},
	church={
		extends="building",
		sprite=5,
		health_bar_height={4,4,6},
		upgrade_options={{"church v2","+2 health",150},{"church v3","+4 health",200},{"max upgrade"}},
		on_trigger=function(self,other)
			local health=({1,2,4})[self.upgrades+1]
			self.commander.health:add(health)
			spawn_entity("pop_text",self:center_x(),other.y-5-self.effect_offset,{
				amount=health,
				type="health"
			})
			sfx(22)
		end
	},
	spark_explosion={
		frames_to_death=18,
		color=7,
		gravity=0.02,
		friction=0.1,
		num_sparks=7,
		speed=2,
		min_angle=0,
		max_angle=360,
		variation=0.1,
		delay=0,
		init=function(self)
			self.sparks={}
			local i
			for i=1,self.num_sparks do
				local angle=self.min_angle/360+(self.max_angle-self.min_angle)*((i-rnd())/self.num_sparks)/360
				local speed=(1-self.variation+rnd(2*self.variation))*self.speed
				add(self.sparks,{
					x=self.x,
					y=self.y,
					vx=speed*cos(angle),
					vy=speed*sin(angle)
				})
			end
			self:update()
		end,
		update=function(self)
			if self.frames_alive>=self.delay then
				local spark
				for spark in all(self.sparks) do
					spark.prev_x,spark.prev_y=spark.x,spark.y
					spark.vy+=self.gravity
					spark.vx*=1-self.friction
					spark.vy*=1-self.friction
					spark.x+=spark.vx
					spark.y+=spark.vy
				end
			end
		end,
		draw=function(self)
			if self.frames_alive>=self.delay then
				local spark
				for spark in all(self.sparks) do
					line(spark.x,spark.y,spark.prev_x,spark.prev_y,self.color)
				end
			end
		end
	},
	character_selector={
		width=40,
		height=36,
		render_layer=9,
		choice=0,
		update=function(self)
			if button_presses[self.player_num][2] then
				self.choice=ternary(self.choice==0,2,self.choice-1)
				-- self.choice=ternary(self.choice==1,2,1)
				sfx(0)
			elseif button_presses[self.player_num][3] then
				self.choice=(self.choice+1)%3
				-- self.choice=ternary(self.choice==1,2,1)
				sfx(0)
			end
		end,
		draw=function(self)
			-- self:draw_outline(8)
			-- draw arrows
			pal(7,ternary(buttons[self.player_num][2],13,7))
			draw_sprite(117,0,11,6,self.x+14,self.y,false,true)
			pal(7,ternary(buttons[self.player_num][3],13,7))
			draw_sprite(117,0,11,6,self.x+14,self.y+30)
			local primary_color=({12,10,8})[self.choice+1]
			local secondary_color=({5,4,2})[self.choice+1]
			pal(3,secondary_color)
			pal(11,primary_color)
			pal(8,primary_color)
			pal(12,primary_color)
			-- draw the character sprite
			draw_sprite(4*self.choice,0,4,6,self.x+17,self.y+20)
			-- draw class name
			draw_sprite(87,7+6*self.choice,40,6,self.x,self.y+10)
		end
	},
	character_select_screen={
		x=48,
		y=59,
		width=31,
		height=22,
		render_layer=8,
		init=function(self)
			self.selectors={
				spawn_entity("character_selector",3,52,{player_num=1}),
				spawn_entity("character_selector",84,52,{player_num=2})
			}
		end,
		update=function(self)
			local class_choices={"witch","thief","knight"}
			if button_presses[1][0] and self.frames_alive>15 then
				button_presses[1][0]=false
				sfx(1)
				sfx(2)
				init_gameplay_scene(class_choices[self.selectors[1].choice+1],class_choices[self.selectors[2].choice+1])
				self.selectors[1]:die()
				self.selectors[2]:die()
				self:die()
			end
		end,
		draw=function(self)
			draw_sprite(24,120,58,8,34,20)
			rectfill(0,self.y-10.5,127,self.y+self.height+10.5,0)
			print("press",self.x+6.5,self.y+0.5,7)
			print("to start",self.x+0.5,self.y+17.5,7)
			palt(3,true)
			draw_sprite(35,31,7,9,self.x+11.5,self.y+6)
			-- self:draw_outline(8)
		end
	},
	game_end_screen={
		update=function(self)
			local x=ternary(self.winning_player_num==1,109,18)
			if self.frames_alive<100 then
				if self.frames_alive%3==0 then
					sfx(18)
				end
				spawn_entity("spark_explosion",x+rnd_int(-8,8),rnd_int(18,32),{
					min_angle=20,
					max_angle=160,
					color=6,--rnd_int(8,10),
					gravity=-0.02,
					speed=1,
					num_sparks=4
				})
			elseif self.frames_alive==100 then
				sfx(17)
				spawn_entity("spark_explosion",x,24,{
					color=7,
					speed=4,
					num_sparks=30,
					variation=0.7,
					frames_to_death=40
				})
			end
		end,
		draw=function(self)
			if self.frames_alive>100 then
				pal(11,commanders[1].colors[2])
				pal(3,commanders[1].colors[5])
				draw_sprite(98,ternary(self.winning_player_num==1,25,31),30,6,3,22)
				pal(11,commanders[2].colors[2])
				pal(3,commanders[2].colors[5])
				draw_sprite(98,ternary(self.winning_player_num==2,25,31),30,6,93,22)
			end
			if self.frames_alive>180 then
				print("press",54.5,59.5,7)
				pal(1,0)
				draw_sprite(35,31,7,9,60,65)
				print("to restart",43.5,76.5,7)
			end
		end
	},
	trigger_effect={
		frames_to_death=7,
		vy=-5,
		render_layer=7,
		init=function(self)
		end,
		update=function(self)
			self.vy=min(0,self.vy+1)
			self:apply_velocity()
		end,
		draw=function(self)
			rectfill(self.x+0.5,self.y+0.5,self.x+6.5,self.y+6.5-self.frames_alive,self.color)
		end
	},
	fireball={
		width=8,
		height=8,
		hit_channel=1, -- buildings
		damage=10,
		frames_to_death=97,
		update=function(self)
			if self.frames_alive%5==0 then
				sfx(25)
			end
			self:apply_velocity()
			spawn_entity("spark_explosion",self.x+rnd_int(2,6),self.y+rnd_int(2,6),{
				color=rnd_int(8,10),
				-- min_angle=300,
				-- max_angle=420,
				variation=0.9,
				frames_to_death=10,
				speed=2,
				friction=0.3
			})
			if commanders then
				local commander
				for commander in all(commanders) do
					local troop
					for troop in all(commander.army.troops) do
						local dx=mid(-100,self:center_x()-troop.x,100)
						local dy=mid(-100,self:center_y()-troop.y,100)
						if dx*dx+dy*dy<4*4 then
							commander.army:destroy_troop(troop)
						end
					end
				end
			end
		end,
		draw=noop
	},
	bolt={
		width=17,
		height=22,
		frames_to_death=8,
		init=function(self)
			spawn_entity("spark_explosion",self:center_x(),self:center_y(),{
				color=10,
				num_sparks=30,
				variation=0.6,
				speed=3	
			})
		end,
		draw=function(self)
			draw_sprite(35,40,17,22,self.x,self.y)
		end
	}
}

function _init()
	game_frames=0
	freeze_frames=0
	screen_shake_frames=0
	init_character_select_scene()
end

-- local skip_frames=0
-- local was_paused=false
function _update(is_paused)
	game_frames=increment_counter(game_frames)
	freeze_frames=decrement_counter(freeze_frames)
	screen_shake_frames=decrement_counter(screen_shake_frames)
	-- skip_frames+=1
	-- if skip_frames%10>0 and not btn(5) then return end
	-- keep track of button presses
	local p
	for p=1,2 do
		local i
		for i=0,5 do
			button_presses[p][i]=btn(i,controllers[p]) and not buttons[p][i]
			buttons[p][i]=btn(i,controllers[p])
		end
	end
	-- update all the entities
	local entity
	for entity in all(entities) do
		if decrement_counter_prop(entity,"frames_to_death") then
			entity:die()
		else
			decrement_counter_prop(entity,"invincibility_frames")
			increment_counter_prop(entity,"frames_alive")
			entity:update()
		end
	end
	-- check for hits
	for i=1,#entities do
		local j
		for j=1,#entities do
			if i!=j and entities[i]:is_hitting(entities[j]) and entities[j].invincibility_frames<=0 then
				entities[i]:on_hit(entities[j])
				entities[j]:on_hurt(entities[i])
			end
		end
	end
	-- check for troop fights
	if commanders then
		for i=1,5 do
			local farthest_left
			local farthest_right
			local j
			local troop
			for troop in all(commanders[1].army.troops) do
				if troop.battle_line==i and (not farthest_right or troop.x>farthest_right.x) then
					farthest_right=troop
				end
			end
			for troop in all(commanders[2].army.troops) do
				if troop.battle_line==i and (not farthest_left or troop.x<farthest_left.x) then
					farthest_left=troop
				end
			end
			if farthest_left and farthest_right and farthest_left.x<=farthest_right.x then
				commanders[1].army:destroy_troop(farthest_right)
				commanders[2].army:destroy_troop(farthest_left)
			end
		end
	end
	-- restart the game
	if game_end_screen and game_end_screen.frames_alive>185 and button_presses[1][0] then
		button_presses[1][0]=false
		init_character_select_scene()
		sfx(1)
	end
	-- end the game
	if commanders and not game_end_screen then
		if commanders[1].health.amount<=0 then
			init_game_end_scene(2)
		elseif commanders[2].health.amount<=0 then
			init_game_end_scene(1)
		end
	end
	-- remove dead entities
	for entity in all(entities) do
		if not entity.is_alive then
			del(entities,entity)
		end
	end
	-- sort entities for rendering
	local i
	for i=1,#entities do
		local j=i
		while j>1 and is_rendered_on_top_of(entities[j-1],entities[j]) do
			entities[j],entities[j-1]=entities[j-1],entities[j]
			j-=1
		end
	end
end

-- local was_paused=false
-- function _paused()
-- end

function _draw()
	-- shake the camera
	local shake_x=0
	if freeze_frames<=0 and screen_shake_frames>0 then
		shake_x=ceil(screen_shake_frames/3)*(game_frames%2*2-1)
	end
	-- clear the screen
	camera(shake_x,0)
	cls(0)
	-- draw the level grounds
	-- camera(0,-1)
	rectfill(level_bounds.left.x+0.5,level_bounds.top.y+0.5,level_bounds.right.x-0.5,level_bounds.bottom.y-0.5,3)
	draw_sprite(0,18,4,5,0,31)
	draw_sprite(0,18,4,5,123,31,true)
	draw_sprite(4,18,1,5,4,31,false,false,119)
	draw_sprite(24,15,4,12,0,100)
	draw_sprite(24,15,4,12,123,100,true)
	draw_sprite(28,15,1,12,4,100,false,false,119)
	-- draw castles
	draw_sprite(ternary(game_end_screen and game_end_screen.winning_player_num==2 and game_end_screen.frames_alive>100,58,29),7,29,20,4,11)
	draw_sprite(ternary(game_end_screen and game_end_screen.winning_player_num==1 and game_end_screen.frames_alive>100,58,29),7,29,20,94,11)
	-- draw drawbridges
	draw_sprite(5,18,7,5,14,31)
	draw_sprite(5,18,7,5,104,31)
	-- draw lines
	local y
	for y=37.5,100.5,6 do
		line(63.5,y,63.5,y+2,5)
	end
	pset(63.5,33.5,11)
	pset(63.5,103.5,11)
	-- draw grass
	-- draw_sprite(19,15,2,3,30,92)
	-- draw_sprite(16,15,3,2,40,37)
	-- draw_sprite(16,15,3,2,75,97)
	-- draw_sprite(19,15,4,3,95,42)
	-- draw the entities' shadows
	-- camera()
	local entity
	for entity in all(entities) do
		entity:draw_shadow()
		pal()
	end
	-- draw the entities
	for entity in all(entities) do
		entity:draw()
		pal()
	end
end

function init_character_select_scene()
	entities={}
	commanders=nil
	game_end_screen=nil
	ball=nil
	spawn_entity("character_select_screen")
end

function init_gameplay_scene(player_1_class,player_2_class)
	commanders={
		spawn_entity(player_1_class,level_bounds.left.x+6,60,{
			player_num=1,
			opposing_player_num=2,
			facing_dir=1,
			is_facing_left=false
		}),
		spawn_entity(player_2_class,level_bounds.right.x-8,60,{
			player_num=2,
			opposing_player_num=1,
			facing_dir=-1,
			is_facing_left=true
		})
	}
	if player_1_class==player_2_class then
		local commander=commanders[rnd_int(1,2)]
		commander.colors={3,11,11,commander.colors[4],3}
	end
	ball=spawn_entity("ball",62,66)
end

function init_game_end_scene(winning_player_num)
	game_end_screen=spawn_entity("game_end_screen",0,0,{
		winning_player_num=winning_player_num
	})
	commanders[1].army.troops={}
	commanders[2].army.troops={}
	if ball then
		ball:despawn()
		ball=nil
	end
end

-- spawns an entity that's an instance of the given class
function spawn_entity(class_name,x,y,args,skip_init)
	local class_def=entity_classes[class_name]
	local entity
	if class_def.extends then
		entity=spawn_entity(class_def.extends,x,y,args,true)
	else
		-- create a default entity
		entity={
			frames_alive=0,
			frames_to_death=0,
			is_alive=true,
			x=x or 0,
			y=y or 0,
			vx=0,
			vy=0,
			width=8,
			height=8,
			collision_indent=2,
			collision_padding=0,
			collision_channel=0,
			platform_channel=0,
			hit_channel=0,
			hurt_channel=0,
			render_layer=5,
			invincibility_frames=0,
			init=noop,
			update=function(self)
				self:apply_velocity()
			end,
			apply_velocity=function(self,speed_mult)
				speed_mult=speed_mult or 1
				-- move in discrete steps if we might collide with something
				if self.collision_channel>0 then
					local max_move_x=min(self.collision_indent,self.width-2*self.collision_indent)-0.1
					local max_move_y=min(self.collision_indent,self.height-2*self.collision_indent)-0.1
					local steps=max(1,ceil(max(abs((self.vx*speed_mult)/max_move_x),abs((self.vy*speed_mult)/max_move_y))))
					local i
					for i=1,steps do
						-- apply velocity
						self.x+=(self.vx*speed_mult)/steps
						self.y+=(self.vy*speed_mult)/steps
						-- check for collisions
						if self:check_for_collisions() then
							return
						end
					end
				-- just move all at once
				else
					self.x+=self.vx*speed_mult
					self.y+=self.vy*speed_mult
				end
			end,
			-- hit functions
			is_hitting=function(self,other)
				return band(self.hit_channel,other.hurt_channel)>0 and objects_overlapping(self,other)
			end,
			on_hit=noop,
			on_hurt=noop,
			-- collision functions
			check_for_collisions=function(self)
				local stop=false
				-- check for collisions against other entities
				local entity
				for entity in all(entities) do
					if entity!=self then
						local collision_dir=self:check_for_collision(entity)
						if collision_dir then
							-- they are colliding!
							stop=stop or self:on_collide(collision_dir,entity)
						end
					end
				end
				-- check for collisions against the level boundaries
				if band(self.collision_channel,1)>0 then
					if self.y+self.height+self.collision_padding>level_bounds.bottom.y then
						stop=stop or self:on_collide("down",level_bounds.bottom)
					elseif self.x+self.width+self.collision_padding>level_bounds.right.x then
						stop=stop or self:on_collide("right",level_bounds.right)
					elseif self.x-self.collision_padding<level_bounds.left.x then
						stop=stop or self:on_collide("left",level_bounds.left)
					elseif self.y-self.collision_padding<level_bounds.top.y then
						stop=stop or self:on_collide("up",level_bounds.top)
					end
				end
				return stop
			end,
			check_for_collision=function(self,other)
				if band(self.collision_channel,other.platform_channel)>0 then
					return objects_colliding(self,other)
				end
			end,
			on_collide=function(self,dir,other)
				self:handle_collision_position(dir,other)
				self:handle_collision_velocity(dir,other)
			end,
			handle_collision_position=function(self,dir,other)
				if dir=="left" then
					self.x=other.x+other.width
				elseif dir=="right" then
					self.x=other.x-self.width
				elseif dir=="up" then
					self.y=other.y+other.height
				elseif dir=="down" then
					self.y=other.y-self.height
				end
			end,
			handle_collision_velocity=function(self,dir,other)
				if dir=="left" then
					self.vx=max(self.vx,other.vx)
				elseif dir=="right" then
					self.vx=min(self.vx,other.vx)
				elseif dir=="up" then
					self.vy=max(self.vy,other.vy)
				elseif dir=="down" then
					self.vy=min(self.vy,other.vy)
				end
			end,
			-- draw functions
			draw=function(self)
				self:draw_outline()
			end,
			draw_shadow=noop,
			draw_outline=function(self,color)
				rect(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,color or 7)
			end,
			-- lifetime functions
			die=function(self)
				if self.is_alive then
					self.is_alive=false
					self:on_death()
				end
			end,
			despawn=function(self)
				self.is_alive=false
			end,
			on_death=noop,
			center_x=function(self)
				return self.x+self.width/2
			end,
			center_y=function(self)
				return self.y+self.height/2
			end
		}
	end
	-- add class-specific properties
	entity.class_name=class_name
	local key,value
	for key,value in pairs(class_def) do
		entity[key]=value
	end
	-- override with passed-in arguments
	for key,value in pairs(args or {}) do
		entity[key]=value
	end
	if not skip_init then
		-- add it to the list of entities
		add(entities,entity)
		-- initialize the entitiy
		entity:init()
	end
	-- return the new entity
	return entity
end

function is_rendered_on_top_of(a,b)
	return ternary(a.render_layer==b.render_layer,a:center_y()>b:center_y(),a.render_layer>b.render_layer)
end

function freeze_and_shake_screen(f,s)
	freeze_frames,screen_shake_frames=max(f,freeze_frames),max(s,screen_shake_frames)
end

-- check to see if two rectangles are overlapping
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	return x1<x2+w2 and x2<x1+w1 and y1<y2+h2 and y2<y1+h1
end

-- check to see if obj1 is overlapping with obj2
function objects_overlapping(obj1,obj2)
	return rects_overlapping(obj1.x,obj1.y,obj1.width,obj1.height,obj2.x,obj2.y,obj2.width,obj2.height)
end

-- check to see if obj1 is colliding into obj2, and if so in which direction
function objects_colliding(obj1,obj2)
	local x1,y1,w1,h1,i,p=obj1.x,obj1.y,obj1.width,obj1.height,obj1.collision_indent,obj1.collision_padding
	local x2,y2,w2,h2=obj2.x,obj2.y,obj2.width,obj2.height
	-- check hitboxes
	if rects_overlapping(x1+i,y1+h1/2,w1-2*i,h1/2+p,x2,y2,w2,h2) and obj1.vy>=obj2.vy then
		return "down"
	elseif rects_overlapping(x1+w1/2,y1+i,w1/2+p,h1-2*i,x2,y2,w2,h2) and obj1.vx>=obj2.vx then
		return "right"
	elseif rects_overlapping(x1-p,y1+i,w1/2+p,h1-2*i,x2,y2,w2,h2) and obj1.vx<=obj2.vx then
		return "left"
	elseif rects_overlapping(x1+i,y1-p,w1-2*i,h1/2+p,x2,y2,w2,h2) and obj1.vy<=obj2.vy then
		return "up"
	end
end

-- checks to see if a point is contained in an object's bounding box
function contains_point(obj,x,y,fudge)
	fudge=fudge or 0
	return obj.x-fudge<x and x<obj.x+obj.width+fudge and obj.y-fudge<y and y<obj.y+obj.height+fudge
end

-- returns the second argument if condition is truthy, otherwise returns the third argument
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	return ternary(n>32000,20000,n+1)
end

-- increment_counter on a property of an object
function increment_counter_prop(obj,key)
	obj[key]=increment_counter(obj[key])
end

-- decrement a counter but not below 0
function decrement_counter(n)
	return max(0,n-1)
end

-- decrement_counter on a property of an object, returns true when it reaches 0
function decrement_counter_prop(obj,key)
	local initial_value=obj[key]
	obj[key]=decrement_counter(initial_value)
	return initial_value>0 and initial_value<=1
end

-- generates a random integer between min_val and max_val, inclusive
function rnd_int(min_val,max_val)
	return flr(min_val+rnd(1+max_val-min_val))
end

-- wrapper for the sspr function
function draw_sprite(sx,sy,sw,sh,x,y,flip_h,flip_y,sw2,sh2)
	sspr(sx,sy,sw,sh,x+0.5,y+0.5,(sw2 or sw),(sh2 or sh),flip_h,flip_y)
end

__gfx__
00b0b000000000000000001000111011101010100000000000100001111100011100000100001101100111110001110000011005555555555555577777777777
0bbb0bbb0bbb0011110001b1001bb1bb1011b1100111110001b11001bbb10001b100001b10001b1b101bbbbb1001b100001b1005555555555555507777777770
044404440fbf001bb1001bbb101bb1bb101bbb1001bbb1001bbb1001bbb10111b11101bbb1001b1b101b1b1b1001b10001b11105555555555555500777777700
044404440fff1111111111b1111bb1bb101bbb1001bbb101bbbbb101111101bbbbb101bbb1001bbb101bbbbb101bbb101bbbbb15555555555555500077777000
0bbb0bbb0bbb1bb1bb1001b100111b11101bbb1001bbb1011bbb110100010111b11101b1b10001b10001bbb101bbbbb10111b105555555555555500007770000
080c080c080c1111111001b100111111101bbb10011111001bbb100111110001b1000011100001b10001b1b1011bbb11001b1005555555555555500000700000
01111111110200000000011100001110001111100000000011111001000100011100000000000111000010100011111000110005555555555555555555555555
1677777776101110000111111111000000100000000000000000000000000000000000000000000000000000003bb003bb3bbbb3bbbbbb3bbbb03bb03bb00005
1777777777116761111777777777100000100000000000000000100000000000000000000000000000000000003bb003bb03bb0003bb03bb03bb3bb03bb00005
17777777771177711d6777767776100001110000000000000000100000000000000000000000000000000000003bb003bb03bb0003bb03bb00003bb03bb00005
17777777771177711d777777d661100001110000000000000001110000000000000000000000000000000000003bb3b3bb03bb0003bb03bb00003bbbbbb00005
17777777771177711d7777671111000011111000000010000001110000000000000000000000000000000000003bbbbbbb03bb0003bb03bbb3bb3bb03bb00005
17777777771177711d7677d610000000111110000000100000111110000000000000000000000000000000000003bb3bb03bbbb003bb003bbbb03bb03bb00005
1777777777117771111166d100000001111111000001110000111110000000000000000000000001000000000003bbbbbb3bb03bb3bbbb3bbbbb3bbbbb000005
1777777777116761000011100000000111111100000111000111111100000000000000000000001100000000000003bb003bb03bb03bb03bb0003bb000000005
1677777776101110b0b55555b333301111111110001111100111111100000000000000010000001110000000000003bb003bb03bb03bb03bb0003bb000000005
11111111111555551b055555b333301111111110001111101111111110000100000000010010011110000000000003bb003bbbbbb03bb03bbb003bbbb0000005
011111111105088088055555bb33311111111111011111111111111110000110000000111011011110100000000003bb003bb03bb03bb03bb0003bb000000005
0222211244428888ee80aa05bbbb300111111100011111111111111111001111000000111111111111110000000003bb003bb03bb3bbbb3bbbbb3bb000000005
2bbbb334222488888e8aa7a54bbbb00111111100111111111111111100001111111001111111111111111003bb3bb3bb003bb3bbbb03bbbb03bb03bb3bbbbbb5
bbbb311444440888880aa7a54444400011111000111111111111111100000111110001111111111111111003bb3bb3bbb03bb03bb03bb03bb3bb03bb003bb005
bb333114222400888009aaa54444400011111001111111111111111000000111110011111111111111110003bbbb03bb3b3bb03bb03bb00003bb03bb003bb005
b3333312444200080000aa052444400011111111111111111111111000000111111111111111111111110003bbbbb3bb3b3bb03bb03bb3bbb3bbbbbb003bb005
00000000000000000003b0002222200011111111111111111111111000000111111111111111111111110003bb3bb3bb03bbb03bb03bbb3bb3bb03bb003bb005
00000000000000000003bb001222200011111111111111111111111000000111111111111111111111110003bb3bb3bb003bb3bbbb03bbbb03bb03bb003bb005
0000000000000000000100bb1111100011111111121112111111111000000111111111211121111111110005555c00c5550003bb003bb3bbbb3bb003bb03bb00
00000000000000000001000001111000111111111222221111111110000001111111112222211111111100055551cc15550003bb003bb03bb03bbb03bb03bb00
00000000000600000061600070070707000e0e0ee0b003bb0003bbbbb3bb03bb3bbbbb3bb000003bb03bb3bbbbb0cc05550003bb003bb03bb03bb3b3bb03bb00
0000000006ddd6006dd1dd60700757070000e00e0ebb03bb0003bb0003bb03bb3bb0003bb000003bb03bb3bb3bbc11c5550003bb3b3bb03bb03bb3b3bb03bb00
000600006ddddd606ddddd6077007007705e0e0ee0bbb3bb0003bb0003bb03bb3bb0003bb000003bb03bb3bb3bb10015550003bbbbbbb03bb03bb03bbb000000
06ddd60066d6d66066d6d66000000000000e0e0e00bb03bb0003bbb003bbbbbb3bbb003bb000003bb03bb3bbbbb555555500003bb3bb03bbbb3bb003bb03bb00
06d6d6000666660066666660000000111110003000b003bb0003bb00003bbbb03bb0003bb000003bbb3bb3bb00055555553bb00003bbbb003bbbb03bbbbb03bb
0666660003bbbe0003bbbe000000011111100111005553bbbbb3bbbbb003bb003bbbbb3bbbbb0003bbbb03bb00055555553bb0003bb03bb3bb03bb3bb00003bb
03bbbe000dd666000dd66600000000111110177710000001105555555555555555555555555555555555555555555555553bb0003bb03bb3bbbb003bb00003bb
0666660003bbbe0003bbbe00000000000001777771000010015555555555555555555555555555555555555555555555553bb0003bb03bb003bbbb3bbb0003bb
06dd66000666660006666600000111111111777771101000105555555555555555555555555555555555555555555555553bb0003bbb3bb3bb03bb3bb0000000
066666000661660006616600001111111111777771010001005555555555555555555555555555555555555555555555553bbbbb03bbbb003bbbb03bbbbb03bb
0d616d000d616d000d616d0000011111111117771110101111555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000111111111111111155555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000001111111111011111055555555555555555555555555555555555555555555555555555555555555555555555555555555555555
000000000000000000000000011111111110000000aa000000005555555555555555555555555555555555555555555555555555555555555555555555555555
000000000000000000000000001111111110000000aa000000005555555555555555555555555555555555555555555555555555555555555555555555555555
004000000040000000400000000000011110000000aa000000005555555555555555555555555555555555555555555555555555555555555555555555555555
644400006444000064440000000000111110000000aaa00000005555555555555555555555555555555555555555555555555555555555555555555555555555
d4240000d4240000d42400000000000111100000000aa00000005555555555555555555555555555555555555555555555555555555555555555555555555555
426419a9426419a9426419a900000000111000000000aa0000005555555555555555555555555555555555555555555555555555555555555555555555555555
2bbb1a9a2bbb1a9a2bbb1a9a0000000111100000000aaa0000005555555555555555555555555555555555555555555555555555555555555555555555555555
666619a9666619a9666619a90000001111100000000a0aa000005555555555555555555555555555555555555555555555555555555555555555555555555555
d6161444d6161444d6161444000000011110000000aa00a000005555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000009a909a909a9000000001110000000a000aa00005555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000001a9a1a9a1a9a00000001111000000aa000a0aaa05555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000019a919a919a90000001111100000a0000a00000a5555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000001444144414440000000111100000a0000a0000005555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000000111000aa0a000aa000005555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000000000000000000000000111100aa0000000a000005555555555555555555555555555555555555555555555555555555555555555555555555555
000000000000000000000000000000011110aa0a0000000a00005555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000001111a00000000000aa0005555555555555555555555555555555555555555555555555555555555555555555555555555
000000000000000000000000000000001110000000000000aa005555555555555555555555555555555555555555555555555555555555555555555555555555
000000000000000000040000000000111110000000000000a0a05555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000400000024444000000011111000000000000a000a5555555555555555555555555555555555555555555555555555555555555555555555555555
0004000000244440024242200000001111100000000000a000005555555555555555555555555555555555555555555555555555555555555555555555555555
002440000242422022272420000000011110000000000a0a00005555555555555555555555555555555555555555555555555555555555555555555555555555
02424200222724202277724000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
22272420227772402717172000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
22777240277717202777772000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
27771720233333200333130000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
033333000eee1e000eeeee0000000000000555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0e1eee000e1eee000e1eee0000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000111100555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000333333000000000000555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000eeeeee000011111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000003333000333333000011111100555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000eeee000420004000011111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00333300003333000422224000000000000555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00eeee00004204000444444001111111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00333300004224000042240001111111100555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00420400004444000044440001111111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00422400004224000042240000000000000555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00444400004444000044440000000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00444400004444000042040000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00420400004204000040040000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00400400004004000040040000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000011111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000600000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000600000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000006d60000011111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
000ddd00000ddd0000d666d000111111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00dd6dd000dd6dd00dd666dd55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00dd6dd00ddd6ddd06d666d655555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00d666d00dd666dd0666b66655555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0066b6600d66b66d066bbb6655555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
006bbb60066bbb660666b6dd55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0066bdd00666b6660666666655555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
006666600dd666660dd6666655555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00661660066616660666166655555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000000000000b000055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000000000000b000055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000b0000003be00055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000b0000003be00055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000b000003be00003bbbe0055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000b000003be0000066600055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0003be0003bbbe00006dd00055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0003be0000666000006660b055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
003bbbe0006dd0b000dd60b055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00066600006660b000b663be55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0006dd0000dd63be00b66d6055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0006660000666d6003be6d6055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
000dd60000666d60006d666055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0006660000d666600066666055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
000d160000d616d000d616d055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
88888888888888888888888855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000805777777057777777057777777005777777057777777005777777057775555555555555555555555555555555555555555555555
80000008800000088000000857770577757770577757770577757770577757770577757770577757775555555555555555555555555555555555555555555555
80000008800000088000000857770577757770577757770577757770577757770577757770577700005555555555555555555555555555555555555555555555
80000008800000088000000857770577757770000057770577757770577757770577757770577757775555555555555555555555555555555555555555555555
80000008800000088000000857770577757770000057770577757770577757770577757770577757775555555555555555555555555555555555555555550153
80000008800000088000000857770577757770000057777777057770577757770577705777777757775555555555555555555555555555555555555555554567
800000088000000880000008566656666566600000566600000566605666566605666000005666566655555555555555555555555555555555555555555589ab
8888888888888888888888880566665665666000005666000000566666605666056660566666605666555555555555555555555555555555555555555555cdef
__sfx__
010b00000057500500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
0108000024155281452b135281352b155301603015130111001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
01060000246202462123621226111f6111b61116611116110c6110661502615016150060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
010a00002456024531245212451124511005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
010800001855018531185211852118055280552b0502b0312b0212b01100500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
010800000c5500c5210c5110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0105000030650246410c63130650246411863118631186210c6210c6210c6210c6110c5320c5420c5220c51200600006000060000600006000060000600006000060000600006000060000600006000060000600
0108000018055280552b0502b0312b0212b0110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010500000701500000000000000008015000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010500000501500000000000000006015000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010900001c05500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000002405500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010900000002500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800002002024051240110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800002402020051200110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010d00000060008625146252162500600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
010800000000000600086250000014625146251462500000000002162500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300002764018642216521c61224652186521c6220e642126320f6300e6200d6100e63008620066200561005620046100261002610016100060000600006000060000600006000060000600006000060000600
0002000012610176200a6200d61003610036000460003600046000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
010b00001823000200182302423024221242120020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200
01100000181401c145181251c15500100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
010800002443518415244351841524435244212441124411084000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400
010b00001852218532185421854218532185221851200500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
01080000183551c3551f3551c3551f355213552435526355283553035030331303110030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300
010200003222032221312212d21127211002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200
01020000066100d6211463115631146310f6210562102611016000160000600006000060000600006000060000600006000060001600016000060000600006000060000600006000060000600006000060000600
010500000000012310163111a321203312435024321243110c3000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300
00050000276301f6411b651326602766114651386602d6610a6510365104651056410b6410c64109631076310162101621066210b6110a6110761104611026110161101611006000060000600006000060000600
010600002b650216511565113651126410f6310c6310a631066210462103621036210261102611026110261101611016110161101611016110000000000000000000000000000000000000000000000000000000
