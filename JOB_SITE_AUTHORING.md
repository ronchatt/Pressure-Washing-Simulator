# Job Site Authoring

Any `Model` or `BasePart` in `Workspace` can become a Phone job without a new script.

## Required attributes

- `JobID` (string): globally unique, using letters, numbers, `_`, or `-`.
- `JobType` (string): `Bench`, `Fence`, `Car`, `Driveway`, `House`, or `Mansion`.
- `PhoneJobEnabled` (boolean): set to `true` only after the model is placed and ready.

Alternatively, tag the object `CleanableJobSite`; it still needs `JobID` and `JobType`.

## Optional Phone and economy attributes

- `DisplayName` (string)
- `RequiredTier` (string)
- `Difficulty` (string)
- `RecommendedWasher` (string)
- `Reward` (number)
- `CompletionThreshold` (number from 50 through 100)

Missing optional values receive safe defaults. At server startup, the site is validated,
converted into a runtime job, scanned for exposed surfaces, added to the Phone catalog,
given customer-water interaction, and connected to waypoints and server progress.

Liquid dirt canvases for cars, driveways, houses, and mansions are client-local and are
created only while that player's job is active. They are destroyed on completion or quit.

The models in `Workspace.MapVariants.Cars` and `Workspace.MapVariants.Houses` already
contain these attributes with `PhoneJobEnabled = false`. Move a model into its final map
location, give it a unique `JobID`, and enable it when it is ready for playtesting.
