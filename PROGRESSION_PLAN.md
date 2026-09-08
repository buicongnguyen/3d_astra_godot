# Unit information and technology progression

Implemented for the Godot edition, September 8, 2026. The Three.js repository remains independent.

## Delivered

- Every selected entity shows current HP, shield, and effective attack damage. Building names and world badges show their level. Blue bars show remaining shields.
- **Info & stats** opens a scrollable field guide for all five buildings and all six units. It explains functions, production, attack intervals, range, counters, costs, supply, support eligibility and upgrade rules. A fixed Close button works on short screens; opening the guide pauses the match.
- The original four units are joined by an original Blender Medic and Engineer, each with five animation clips and editable source files.
- Every building supports levels 1–3. Command core level controls which other building upgrades are available. Training cannot overlap an upgrade, and all prerequisites and resource failures produce player messages.
- Shields absorb damage before HP. They recharge at 4 points/second after five seconds without damage. Healing and repair restore HP only.
- AI uses the same resources and progression rules. It leaves production queues room to drain when an upgrade is due.

## Six-unit roster

Base values, before weapon research. Attack means damage per hit; shields are additional rechargeable hit points, not percentage armor.

| Unit | HP | Shield | Attack | Interval | Purpose / production |
| --- | ---: | ---: | ---: | --- | --- |
| Harvester | 55 | 10 | 4 | 1 s | Gather and construct; Command core |
| Vanguard | 150 | 60 | 15 | 0.85 s | Close assault; 1.6× against Rangers; Barracks |
| Ranger | 85 | 25 | 12 | 1.05 s | Ranged fire; 1.6× against Breakers; Barracks |
| Breaker | 300 | 80 | 30 | 1.7 s | Artillery with secondary splash damage; Foundry |
| Medic | 75 | 30 | 0 | — | Restore 12 infantry HP/s; level 2 Barracks |
| Engineer | 100 | 30 | 0 | — | Restore 18 building/Breaker HP/s; level 2 Foundry |

Medics heal other friendly infantry, including Harvesters and Engineers. Engineers repair completed buildings and Breakers. Neither support unit attacks, heals itself, revives a casualty, completes construction, or refills shields. Support uses range 6, requires a clear line, and consumes no resources. Idle support units automatically help injured allies in range. **Support → ally** orders them to follow a specific target on desktop or touch; desktop right-click is also contextual. Attack-move lets them move with an army and stop to support nearby injuries.

## Buildings and three match stages

| Building | Base HP | Base shield | Base attack | Function |
| --- | ---: | ---: | ---: | --- |
| Command core | 2200 | 150 | 0 | Resource drop-off, Harvesters, 15 supply, technology levels |
| Supply relay | 450 | 40 | 0 | 10 / 15 / 20 supply at levels 1 / 2 / 3 |
| Barracks | 850 | 60 | 0 | Vanguards, Rangers; Medics at level 2 |
| Foundry | 1100 | 90 | 0 | Breakers, Engineers at level 2, one-time +10% combat-unit damage research |
| Sentinel tower | 650 | 50 | 19 | Automatic defense, 1.2 s attack interval, range 13 |

1. **Establish:** gather both resources, build supply and a mixed army.
2. **Support:** upgrade a Command core, then production buildings to level 2; add healing and repairs.
3. **Fortify:** advance to level 3 for stronger buildings, towers and faster production; defeat enemy cores.

These are technology stages within the two existing skirmish maps, not a new campaign or three new maps. A player can still win with an early attack.

| Upgrade | Level 2 | Level 3 |
| --- | --- | --- |
| Command core cost | 200 alloy / 100 energy | 350 alloy / 175 energy |
| Other building cost | 100 alloy / 50 energy | 200 alloy / 100 energy |
| Duration | 20 s | 30 s |
| Max HP versus base | +25% | +50% total |
| Max shield versus base | +25 | +50 total |
| Production rate | 1.2× | 1.4× |
| Tower attack versus base | +25% | +50% total |

Existing damage is retained as an absolute HP deficit when max HP increases. Added shield capacity recharges normally. Existing units retain their base stats; building upgrades accelerate future production. Weapon research is the separate +10% damage effect for existing and future combat units. Supply remains capped at 100. Canceling a level upgrade refunds its exact cost once; destruction does not refund it. Production must be finished or canceled before upgrading. Lowering surviving core technology by destroying a higher-level core does not remove completed upgrades or already-unlocked units.

## Review and verification

1. **Rules and economy:** verified ownership, costs, prerequisites, queue exclusivity, single refunds, finite shield overflow, recharge delay, support eligibility, line of sight and HP caps. Added 37 focused progression checks alongside 47 existing match/economy/navigation checks.
2. **Integration:** verified all 11 Blender entity models and 30 unit clips, guide pause restoration, building picking, settings and restart cleanup. Fixed AI production queues preventing upgrades and kept level-badge colors synchronized with army settings.
3. **Browser interaction:** exercised mouse and touch at desktop and phone sizes, including guide open/close, exact upgrade cancellation, Medic unlock and production, explicit Support targeting and level 3 technology. The existing construction, production, fog, settings, camera and restart tests remain in the suite.

CI runs the progression suite before exporting Web and Windows and deploying GitHub Pages. Physical Android/iOS testing and broader competitive balance remain future work.

## Suggested next iteration

- Separate scenario missions with objectives and saved completion: defend a relay, escort an Engineer, then assault a fortified base.
- Visible health/shield totals for mixed selections and a dedicated production queue panel.
- Support prioritization controls and repair-cost tuning informed by longer playtests.
- Distinct building silhouettes at higher levels, beyond the current level badges.
- Physical-device performance measurements before adding larger armies or more visual effects.
