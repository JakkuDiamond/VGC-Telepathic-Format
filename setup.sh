#!/usr/bin/env bash
# One-file setup: private Pokemon Showdown server with the "VGC Reg M-C Multi Lead+Back" format.
# The patch is built into this file, so nothing else needs to be copied. Requires: git, Node.js >= 22.18, npm.
set -euo pipefail
COMMIT=d601443456c795f77c6e4f2b5b459167f2b10a3c   # Showdown version this was tested against
PATCH_VERSION=5d8bb29b

echo "[1/5] setup.sh patch version $PATCH_VERSION"
PATCH_FILE="$(mktemp)"
cat >"$PATCH_FILE" <<'VGC_PATCH_EOF'
diff --git a/config/formats.ts b/config/formats.ts
index 9a65139..0006c54 100644
--- a/config/formats.ts
+++ b/config/formats.ts
@@ -18,6 +18,18 @@ The column value will be ignored for repeat sections.
 */
 
 export const Formats: import('../sim/dex-formats').FormatList = [
+	{
+		section: "Custom",
+	},
+	{
+		name: "[Gen 9 Champions] VGC Reg M-C Multi Lead+Back",
+		desc: `4 players, 2v2 teams, built on VGC 2026 Reg M-C rules (incl. Open Team Sheets, which all 4 players must accept). Players 1 and 2 bring a team of 6; players 3 and 4 use a copy of their ally's team. Each player picks 2 (lead, then back), with no overlap between allies, and allies see each other's picks. In battle you can also switch to your ally's benched Pok&eacute;mon.`,
+		mod: 'champions',
+		gameType: 'multi',
+		searchShow: false,
+		ruleset: ['[Gen 9 Champions] VGC 2026 Reg M-C', '!! Picked Team Size = 2', 'Shared Ally Team', 'Shared Bench', 'Confusion Friendly Fire', 'Infatuation Friendly Fire', 'Ally Switch Trade', 'Team Healing', 'No Chat'],
+	},
+
 
 	// S/V Singles
 	///////////////////////////////////////////////////////////////////
diff --git a/data/conditions.ts b/data/conditions.ts
index c72966a..952d546 100644
--- a/data/conditions.ts
+++ b/data/conditions.ts
@@ -188,10 +188,17 @@ export const Conditions: import('../sim/dex-conditions').ConditionDataTable = {
 				return;
 			}
 			this.activeTarget = pokemon;
-			const damage = this.actions.getConfusionDamage(pokemon, 40);
+			let victim = pokemon;
+			if (this.ruleTable.has('confusionfriendlyfire')) {
+				// Confusion Friendly Fire: 50% chance to hurt the adjacent ally instead of itself
+				const ally = pokemon.adjacentAllies()[0];
+				if (ally && this.randomChance(1, 2)) victim = ally;
+			}
+			const damage = this.actions.getConfusionDamage(pokemon, 40, victim);
 			if (typeof damage !== 'number') throw new Error("Confusion damage not dealt");
 			const activeMove = { id: this.toID('confused'), effectType: 'Move', type: '???' };
-			this.damage(damage, pokemon, pokemon, activeMove as ActiveMove);
+			if (victim !== pokemon) this.add('-message', `${pokemon.name} hurt its ally ${victim.name} in its confusion!`);
+			this.damage(damage, victim, pokemon, activeMove as ActiveMove);
 			return false;
 		},
 	},
diff --git a/data/moves.ts b/data/moves.ts
index 2808538..1a23d8c 100644
--- a/data/moves.ts
+++ b/data/moves.ts
@@ -312,6 +312,17 @@ export const Moves: import('../sim/dex-moves').MoveDataTable = {
 			return pokemon.addVolatile('allyswitch');
 		},
 		onHit(pokemon) {
+			if (this.ruleTable.has('allyswitchtrade') && this.gameType === 'multi') {
+				// Ally Switch Trade: trade active Pokemon (and who controls them) with the ally
+				const ally = pokemon.adjacentAllies()[0];
+				if (!ally || ally.fainted) {
+					this.add('-fail', pokemon, 'move: Ally Switch');
+					this.attrLastMove('[still]');
+					return this.NOT_FAIL;
+				}
+				this.tradeActiveAllies(pokemon, ally);
+				return;
+			}
 			let success = true;
 			// Fail in formats where you don't control allies
 			if (this.gameType !== 'doubles' && this.gameType !== 'triples') success = false;
@@ -743,6 +754,17 @@ export const Moves: import('../sim/dex-moves').MoveDataTable = {
 			onBeforeMove(pokemon, target, move) {
 				this.add('-activate', pokemon, 'move: Attract', '[of] ' + this.effectState.source);
 				if (this.randomChance(1, 2)) {
+					if (this.ruleTable.has('infatuationfriendlyfire') && move.category !== 'Status' &&
+						['normal', 'any', 'adjacentFoe', 'randomNormal'].includes(move.target)) {
+						// Infatuation Friendly Fire: 50% of the time, attack the ally instead of being immobilized
+						const ally = pokemon.adjacentAllies()[0];
+						if (ally && this.randomChance(1, 2)) {
+							this.add('-message', `${pokemon.name} is so infatuated it attacks its ally ${ally.name}!`);
+							pokemon.deductPP(move.id, 1, ally);
+							this.actions.useMove(move, pokemon, { target: ally });
+							return false;
+						}
+					}
 					this.add('cant', pokemon, 'Attract');
 					return false;
 				}
@@ -15115,9 +15137,10 @@ export const Moves: import('../sim/dex-moves').MoveDataTable = {
 		priority: 0,
 		flags: { heal: 1, nosketch: 1 },
 		onTryHit(source) {
-			if (!source.side.pokemon.filter(ally => ally.fainted).length) {
-				return false;
-			}
+			if (source.side.pokemon.some(ally => ally.fainted)) return;
+			// Team Healing: fainted Pokemon on the ally's side count too
+			if (this.ruleTable.has('teamhealing') && source.side.allySide?.pokemon.some(ally => ally.fainted)) return;
+			return false;
 		},
 		slotCondition: 'revivalblessing',
 		// No this not a real switchout move
diff --git a/data/rulesets.ts b/data/rulesets.ts
index 5103c04..8dc25f0 100644
--- a/data/rulesets.ts
+++ b/data/rulesets.ts
@@ -775,6 +775,70 @@ export const Rulesets: import('../sim/dex-formats').FormatDataTable = {
 			'Timer Add Per Turn = 5', 'Timer Max Per Turn = 15', 'Timer Max First Turn = 40',
 		],
 	},
+	hideallybench: {
+		effectType: 'Rule',
+		name: 'Hide Ally Bench',
+		desc: "In multi battles, hides your teammate's unrevealed Pok&eacute;mon (their back Pok&eacute;mon) from you until they are sent out",
+		onBegin() {
+			this.add('rule', 'Hide Ally Bench: Your teammate\'s back Pokemon is hidden until it is sent out');
+		},
+	},
+	nochat: {
+		effectType: 'Rule',
+		name: 'No Chat',
+		desc: "Disables chat in this battle room for everyone, and blocks private messages between the battle's players. Battle buttons and commands (including Open Team Sheets Accept/Reject) still work",
+		onBegin() {
+			this.add('rule', 'No Chat: Chat is disabled in this battle.');
+		},
+	},
+	allyswitchtrade: {
+		effectType: 'Rule',
+		name: 'Ally Switch Trade',
+		desc: "In multi battles, Ally Switch trades the user's active Pok&eacute;mon with its ally's active Pok&eacute;mon, so the two players swap control of them",
+		onBegin() {
+			this.add('rule', 'Ally Switch Trade: Ally Switch swaps your active Pokemon with your ally\'s, and you swap control of them.');
+		},
+	},
+	teamhealing: {
+		effectType: 'Rule',
+		name: 'Team Healing',
+		desc: "In multi battles, Revival Blessing can revive any fainted Pok&eacute;mon on the team of 4, including ones your ally controls (Heal Bell and Aromatherapy already cure the whole team)",
+		onBegin() {
+			this.add('rule', 'Team Healing: Revival Blessing can revive your ally\'s fainted Pokemon too.');
+		},
+	},
+	infatuationfriendlyfire: {
+		effectType: 'Rule',
+		name: 'Infatuation Friendly Fire',
+		desc: "When an infatuated Pok&eacute;mon would be immobilized by love, there is a 50% chance it uses its single-target damaging move on its ally instead",
+		onBegin() {
+			this.add('rule', 'Infatuation Friendly Fire: An infatuated Pokemon may attack its ally instead of being immobilized.');
+		},
+	},
+	confusionfriendlyfire: {
+		effectType: 'Rule',
+		name: 'Confusion Friendly Fire',
+		desc: "When a confused Pok&eacute;mon hurts itself in its confusion, there is a 50% chance it hits its ally instead (using its Attack against the ally's Defense)",
+		onBegin() {
+			this.add('rule', 'Confusion Friendly Fire: A confused Pokemon may hit its ally instead of itself.');
+		},
+	},
+	sharedbench: {
+		effectType: 'Rule',
+		name: 'Shared Bench',
+		desc: "In multi battles, each player can switch to any benched Pok&eacute;mon on their team, including ones their ally picked (but not the ally's active Pok&eacute;mon)",
+		onBegin() {
+			this.add('rule', 'Shared Bench: You can switch to any benched Pokemon on your team, including your ally\'s.');
+		},
+	},
+	sharedallyteam: {
+		effectType: 'Rule',
+		name: 'Shared Ally Team',
+		desc: "In multi battles, only players 1 and 2 bring teams; players 3 and 4 get a copy of their ally's team. Allies cannot pick the same Pok&eacute;mon, and are told when the other picks",
+		onBegin() {
+			this.add('rule', 'Shared Ally Team: Players 3 and 4 pick from their ally\'s team. Allies cannot pick the same Pokemon.');
+		},
+	},
 	vgctimer: {
 		effectType: 'Rule',
 		name: 'VGC Timer',
diff --git a/server/chat-commands/core.ts b/server/chat-commands/core.ts
index 6e9f0ae..6a210ed 100644
--- a/server/chat-commands/core.ts
+++ b/server/chat-commands/core.ts
@@ -1285,10 +1285,15 @@ export const commands: Chat.ChatCommands = {
 
 		let playerOpts = undefined;
 		if (!player.hasTeam) {
-			const ladder = Ladders(battle.format);
-			const ready = await ladder.prepBattle(connection, 'challenge');
-			if (!ready) return;
-			playerOpts = ready.settings;
+			if ((slot === 'p3' || slot === 'p4') && Dex.formats.getRuleTable(Dex.formats.get(battle.format)).has('sharedallyteam')) {
+				// Shared Ally Team: the sim gives this player a copy of their ally's team
+				playerOpts = {};
+			} else {
+				const ladder = Ladders(battle.format);
+				const ready = await ladder.prepBattle(connection, 'challenge');
+				if (!ready) return;
+				playerOpts = ready.settings;
+			}
 		}
 
 		const fromUser = Ladders.challenges.accept(this);
diff --git a/server/chat.ts b/server/chat.ts
index 2918f4f..26cc727 100644
--- a/server/chat.ts
+++ b/server/chat.ts
@@ -1149,6 +1149,20 @@ export class CommandContext extends MessageContext {
 		const user = this.user;
 		const connection = this.connection;
 
+		// No Chat rule: no chat in the battle room, and no PMs between the battle's players
+		if (room?.battle && Dex.formats.getRuleTable(Dex.formats.get(room.battle.format)).has('nochat')) {
+			throw new Chat.ErrorMessage(`Chat is disabled in this format. You can still use the battle buttons and commands.`);
+		}
+		if (targetUser) {
+			for (const gameRoomid of user.games) {
+				const battle = Rooms.get(gameRoomid)?.battle;
+				if (battle && battle.playerTable[targetUser.id] &&
+					Dex.formats.getRuleTable(Dex.formats.get(battle.format)).has('nochat')) {
+					throw new Chat.ErrorMessage(`Private messages are disabled between players in this format's battles.`);
+				}
+			}
+		}
+
 		if (!user.named) {
 			throw new Chat.ErrorMessage(this.TL`You must choose a name before you can talk.`);
 		}
diff --git a/sim/battle-actions.ts b/sim/battle-actions.ts
index 634eafc..963df81 100644
--- a/sim/battle-actions.ts
+++ b/sim/battle-actions.ts
@@ -1901,11 +1901,12 @@ export class BattleActions {
 	 * context for its damage, unlike the regular damage formula (though this only comes up
 	 * for base damage).
 	 */
-	getConfusionDamage(pokemon: Pokemon, basePower: number) {
+	getConfusionDamage(pokemon: Pokemon, basePower: number, target: Pokemon = pokemon) {
 		const tr = this.battle.trunc;
 
 		const attack = pokemon.calculateStat('atk', pokemon.boosts['atk']);
-		const defense = pokemon.calculateStat('def', pokemon.boosts['def']);
+		// Confusion Friendly Fire: the confused Pokemon can hit its ally, using the ally's Defense
+		const defense = target.calculateStat('def', target.boosts['def']);
 		const level = pokemon.level;
 		const baseDamage = tr(tr(tr(tr(2 * level / 5 + 2) * basePower * attack) / defense) / 50) + 2;
 
diff --git a/sim/battle.ts b/sim/battle.ts
index 6dc37c3..3132548 100644
--- a/sim/battle.ts
+++ b/sim/battle.ts
@@ -1437,7 +1437,7 @@ export class Battle {
 		case 'switch':
 			for (let i = 0; i < this.sides.length; i++) {
 				const side = this.sides[i];
-				if (!side.pokemonLeft) continue;
+				if (!side.pokemonLeft && !side.getSharedBench().length) continue;
 				const switchTable = side.active.map(pokemon => !!pokemon?.switchFlag);
 				if (switchTable.some(Boolean)) {
 					requests[i] = { forceSwitch: switchTable, side: side.getRequestData() };
@@ -1577,6 +1577,45 @@ export class Battle {
 		return true;
 	}
 
+	/** Ally Switch Trade rule: two allied active Pokemon trade places, and so do their controllers */
+	tradeActiveAllies(a: Pokemon, b: Pokemon) {
+		const sideA = a.side;
+		const sideB = b.side;
+		const posA = a.position;
+		const posB = b.position;
+		sideA.pokemon[posA] = b;
+		sideB.pokemon[posB] = a;
+		sideA.active[posA] = b;
+		sideB.active[posB] = a;
+		a.side = sideB;
+		b.side = sideA;
+		a.position = posB;
+		b.position = posA;
+		a.fullname = `${sideB.id}: ${a.name}`;
+		b.fullname = `${sideA.id}: ${b.name}`;
+		this.add('-message', `${sideA.name} and ${sideB.name} traded ${a.name} and ${b.name} with Ally Switch!`);
+		this.add('switch', a, a.getFullDetails);
+		this.add('switch', b, b.getFullDetails);
+	}
+
+	/** Shared Bench rule: moves a benched Pokemon from one ally's side to the other's */
+	transferToSide(pokemon: Pokemon, side: Side) {
+		const from = pokemon.side;
+		from.pokemon.splice(pokemon.position, 1);
+		from.pokemon.forEach((mon, i) => {
+			mon.position = i;
+		});
+		if (!pokemon.fainted) from.pokemonLeft--;
+		pokemon.side = side;
+		pokemon.fullname = `${side.id}: ${pokemon.name}`;
+		pokemon.position = side.pokemon.length;
+		side.pokemon.push(pokemon);
+		if (!pokemon.fainted) side.pokemonLeft++;
+		this.add('-hint', `${side.name} sends out ${from.name}'s ${pokemon.name}!`);
+		this.add('teamsize', from.id, from.pokemon.length);
+		this.add('teamsize', side.id, side.pokemon.length);
+	}
+
 	canSwitch(side: Side) {
 		return this.possibleSwitches(side).length;
 	}
@@ -1587,7 +1626,8 @@ export class Battle {
 	}
 
 	private possibleSwitches(side: Side) {
-		if (!side.pokemonLeft) return [];
+		const sharedBench = side.getSharedBench();
+		if (!side.pokemonLeft && !sharedBench.length) return [];
 
 		// should only be relevant for Gen 3
 		const queuedSwitchIns = this.queue.getSwitches(side).map(action => action.target);
@@ -1599,6 +1639,10 @@ export class Battle {
 				canSwitchIn.push(pokemon);
 			}
 		}
+		// Shared Bench: the ally's benched Pokemon are also options
+		for (const pokemon of sharedBench) {
+			if (!queuedSwitchIns.includes(pokemon)) canSwitchIn.push(pokemon);
+		}
 		return canSwitchIn;
 	}
 
@@ -2813,14 +2857,16 @@ export class Battle {
 			return;
 		case 'instaswitch':
 		case 'switch':
+			if (action.target.side !== action.pokemon.side) this.transferToSide(action.target, action.pokemon.side);
 			if (action.choice === 'switch' && action.pokemon.status) {
 				this.singleEvent('CheckShow', this.dex.abilities.getByID('naturalcure' as ID), null, action.pokemon);
 			}
 			this.actions.switchIn(action.target, action.pokemon.position, action.sourceEffect);
 			break;
 		case 'revivalblessing':
-			action.pokemon.side.pokemonLeft++;
-			if (action.target.position < action.pokemon.side.active.length) {
+			// (the target may be on the ally's side with the Team Healing rule)
+			action.target.side.pokemonLeft++;
+			if (action.target.position < action.target.side.active.length) {
 				this.queue.addChoice({
 					choice: 'instaswitch',
 					pokemon: action.target,
@@ -3107,6 +3153,10 @@ export class Battle {
 			}
 		}
 
+		if (side.requestState === 'teampreview' && side.allySide && side.choice.actions.length &&
+			this.ruleTable.has('sharedallyteam')) {
+			this.addSplit(side.allySide.id, ['-hint', `${side.name} took back their pick.`]);
+		}
 		side.clearChoice();
 
 		if (updated) side.emitRequest(side.activeRequest!, true);
@@ -3287,6 +3337,10 @@ export class Battle {
 		const slotNum = parseInt(slot[1]) - 1;
 		if (!this.sides[slotNum]) {
 			// create player
+			if (slotNum >= 2 && !options.team && this.ruleTable.has('sharedallyteam') && this.sides[slotNum - 2]) {
+				// Shared Ally Team: players 3 and 4 use a copy of their ally's team
+				options.team = Teams.pack(this.sides[slotNum - 2].team);
+			}
 			const team = this.getTeam(options);
 			side = new Side(options.name || `Player ${slotNum + 1}`, this, slotNum, team);
 			if (options.avatar) side.avatar = `${options.avatar}`;
diff --git a/sim/pokemon.ts b/sim/pokemon.ts
index d46c1f5..a23aebb 100644
--- a/sim/pokemon.ts
+++ b/sim/pokemon.ts
@@ -45,13 +45,13 @@ export const RESTORATIVE_BERRIES = new Set([
 ] as ID[]);
 
 export class Pokemon {
-	readonly side: Side;
+	side: Side;
 	readonly battle: Battle;
 
 	readonly set: PokemonSet;
 	readonly name: string;
 	/** `` `${sideid}: ${name}` `` - used to refer to pokemon in the protocol */
-	readonly fullname: string;
+	fullname: string;
 	readonly level: number;
 	readonly gender: GenderName;
 	readonly happiness: number;
diff --git a/sim/side.ts b/sim/side.ts
index 5e8071c..d3657a0 100644
--- a/sim/side.ts
+++ b/sim/side.ts
@@ -354,15 +354,54 @@ export class Side {
 		return `${this.id}: ${this.name}`;
 	}
 
+	/**
+	 * Shared Bench rule: the ally's benched, unfainted Pokemon, which this player may also switch in.
+	 * (Not available during team preview.)
+	 */
+	getSharedBench(): Pokemon[] {
+		const ally = this.allySide;
+		if (!ally || this.battle.turn < 1 || !this.battle.ruleTable.has('sharedbench')) return [];
+		return ally.pokemon.slice(ally.active.length).filter(pokemon => !pokemon.fainted);
+	}
+
+	/** Team Healing rule: while Revival Blessing is choosing, the ally's fainted Pokemon can be chosen too */
+	getReviveTargets(): Pokemon[] {
+		const ally = this.allySide;
+		if (!ally || !this.battle.ruleTable.has('teamhealing')) return [];
+		const reviving = this.active.some(pokemon => pokemon && this.slotConditions[pokemon.position]['revivalblessing']);
+		if (!reviving) return [];
+		return ally.pokemon.filter(pokemon => pokemon.fainted);
+	}
+
+	/** Shared Bench rule: has the ally already chosen to switch this Pokemon in this turn? */
+	isClaimedByAlly(pokemon: Pokemon): boolean {
+		const ally = this.allySide;
+		if (!ally || !this.battle.ruleTable.has('sharedbench')) return false;
+		return ally.choice.actions.some(action =>
+			(action.choice === 'switch' || action.choice === 'instaswitch') && action.target === pokemon);
+	}
+
 	getRequestData(forAlly?: boolean): SideRequestData {
 		const data: SideRequestData = {
 			name: this.name,
 			id: this.id,
 			pokemon: [] as PokemonSwitchRequestData[],
 		};
+		const hideBench = !!forAlly && this.battle.ruleTable.has('hideallybench');
 		for (const pokemon of this.pokemon) {
+			// Hide Ally Bench: a teammate can't see Pokemon that have never been sent out
+			if (hideBench && !pokemon.isActive && !pokemon.previouslySwitchedIn) continue;
 			data.pokemon.push(pokemon.getSwitchRequestData(forAlly));
 		}
+		if (!forAlly) {
+			// Shared Bench / Team Healing: list the ally's Pokemon as extra switch (or revive) options
+			const extras = this.getReviveTargets();
+			for (const pokemon of extras.length ? extras : this.getSharedBench()) {
+				const entry = pokemon.getSwitchRequestData();
+				entry.ident = `${this.id}: ${pokemon.name}`;
+				data.pokemon.push(entry);
+			}
+		}
 		return data;
 	}
 
@@ -924,6 +963,9 @@ export class Side {
 			return this.emitChoiceError(`Can't switch: You sent more choices than unfainted Pokémon`);
 		}
 		const pokemon = this.active[index];
+		const reviveTargets = this.getReviveTargets();
+		const sharedBench = reviveTargets.length ? reviveTargets : this.getSharedBench();
+		const pool = sharedBench.length ? [...this.pokemon, ...sharedBench] : this.pokemon;
 		let slot;
 		if (!slotText) {
 			if (this.requestState !== 'switch') {
@@ -935,7 +977,14 @@ export class Side {
 			} else {
 				if (!this.choice.forcedSwitchesLeft) return this.choosePass();
 				slot = this.active.length;
-				while (this.choice.switchIns.has(slot) || this.pokemon[slot].fainted) slot++;
+				while (slot < pool.length && (this.choice.switchIns.has(slot) || pool[slot].fainted ||
+					this.isClaimedByAlly(pool[slot]))) slot++;
+				if (slot >= pool.length) {
+					// Shared Bench: the ally already claimed everything this player could switch to
+					this.choice.forcedSwitchesLeft = 0;
+					this.choice.forcedPassesLeft++;
+					return this.choosePass();
+				}
 			}
 		} else {
 			slot = parseInt(slotText) - 1;
@@ -943,7 +992,7 @@ export class Side {
 		if (isNaN(slot) || slot < 0) {
 			// maybe it's a name/species id!
 			slot = -1;
-			for (const [i, mon] of this.pokemon.entries()) {
+			for (const [i, mon] of pool.entries()) {
 				if (slotText!.toLowerCase() === mon.name.toLowerCase() || toID(slotText) === mon.species.id) {
 					slot = i;
 					break;
@@ -953,14 +1002,14 @@ export class Side {
 				return this.emitChoiceError(`Can't switch: You do not have a Pokémon named "${slotText!}" to switch to`);
 			}
 		}
-		if (slot >= this.pokemon.length) {
+		if (slot >= pool.length) {
 			return this.emitChoiceError(`Can't switch: You do not have a Pokémon in slot ${slot + 1} to switch to`);
 		} else if (slot < this.active.length && !this.slotConditions[pokemon.position]['revivalblessing']) {
 			return this.emitChoiceError(`Can't switch: You can't switch to an active Pokémon`);
 		} else if (this.choice.switchIns.has(slot)) {
 			return this.emitChoiceError(`Can't switch: The Pokémon in slot ${slot + 1} can only switch in once`);
 		}
-		const targetPokemon = this.pokemon[slot];
+		const targetPokemon = pool[slot];
 
 		if (this.slotConditions[pokemon.position]['revivalblessing']) {
 			if (!targetPokemon.fainted) {
@@ -981,6 +1030,17 @@ export class Side {
 			return this.emitChoiceError(`Can't switch: You can't switch to a fainted Pokémon`);
 		}
 
+		if (this.isClaimedByAlly(targetPokemon)) {
+			const anotherOption = pool.some((mon, i) => i >= this.active.length && !mon.fainted &&
+				!this.choice.switchIns.has(i) && !this.isClaimedByAlly(mon));
+			if (!anotherOption && this.requestState === 'switch') {
+				this.choice.forcedSwitchesLeft = 0;
+				this.choice.forcedPassesLeft++;
+				return this.choosePass();
+			}
+			return this.emitChoiceError(`Can't switch: ${this.allySide!.name} is already switching in ${targetPokemon.name}`);
+		}
+
 		if (this.requestState === 'move') {
 			if (pokemon.trapped) {
 				return this.emitChoiceError(`Can't switch: The active Pokémon is trapped`, { pokemon, update: req => {
@@ -1070,6 +1130,27 @@ export class Side {
 			}
 		}
 
+		if (ruleTable.has('sharedallyteam') && this.allySide) {
+			// Shared Ally Team: allies pick from the same Pokemon, so they cannot overlap
+			const ally = this.allySide;
+			const taken = new Set<number>();
+			for (const action of ally.choice.actions) {
+				if (action.choice === 'team' && action.pokemon) taken.add(ally.pokemon.indexOf(action.pokemon));
+			}
+			if (!data) {
+				// auto-choose: skip what the ally already picked
+				positions = [...this.pokemon.keys()].filter(i => !taken.has(i));
+				positions.splice(pickedTeamSize);
+			} else {
+				const clash = positions.filter(pos => taken.has(pos));
+				if (clash.length) {
+					return this.emitChoiceError(
+						`Can't choose for Team Preview: ${ally.name} already picked ${clash.map(pos => this.pokemon[pos].name).join(', ')}. Choose different Pokémon.`
+					);
+				}
+			}
+		}
+
 		const result = ruleTable.onChooseTeam?.[0].call(this.battle, positions, this.pokemon, !data);
 		if (result) {
 			if (typeof result === 'string') {
@@ -1091,6 +1172,12 @@ export class Side {
 			});
 		}
 
+		if (ruleTable.has('sharedallyteam') && this.allySide) {
+			const labels = ['lead', 'back'];
+			const picked = positions.map((pos, i) => `${this.pokemon[pos].name} (${labels[i] || `slot ${i + 1}`})`);
+			this.battle.addSplit(this.allySide.id, ['-hint', `${this.name} picked ${picked.join(', ')}.`]);
+		}
+
 		return true;
 	}
 
VGC_PATCH_EOF
# Windows line endings would break the patch; remove them.
tr -d '\r' <"$PATCH_FILE" >"$PATCH_FILE.lf"

echo "[2/5] Downloading Pokemon Showdown..."
if [ ! -d pokemon-showdown ]; then
  git clone https://github.com/smogon/pokemon-showdown.git
fi
cd pokemon-showdown
git checkout -q "$COMMIT"
# Discard any earlier version of our changes so the latest patch always applies cleanly.
git reset -q --hard "$COMMIT"

echo "[3/5] Applying the custom format and rules..."
if ! git apply "$PATCH_FILE.lf"; then
  echo "ERROR: could not apply the patch. Delete the pokemon-showdown folder (rm -rf pokemon-showdown) and run ./setup.sh again." >&2
  exit 1
fi
for rule in "Shared Ally Team" "Shared Bench" "Confusion Friendly Fire" "Infatuation Friendly Fire" "Ally Switch Trade" "Team Healing" "No Chat"; do
  grep -q "name: '$rule'" data/rulesets.ts || { echo "ERROR: rule '$rule' missing after patching." >&2; exit 1; }
done
echo "OK: custom rules installed (Shared Ally Team, Shared Bench, Confusion Friendly Fire, Infatuation Friendly Fire, Ally Switch Trade, Team Healing, No Chat)."

echo "[4/5] Installing dependencies (this takes a few minutes)..."
npm install
cp -n config/config-example.js config/config.js 2>/dev/null || true
# Dev-server convenience: log in with any name, no password.
sed -i 's/^exports.noguestsecurity = false;/exports.noguestsecurity = true;/' config/config.js

echo "[5/5] Building..."
node build

echo
echo "Done. Start the server with:  ./start-online.sh   (from the folder that contains this script)"
