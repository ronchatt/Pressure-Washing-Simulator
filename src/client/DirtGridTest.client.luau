--!strict

-- The development dirt grid is server-replicated as of Prompt 4 so cleaning
-- requests refer to Instances that WasherServer can validate. This client
-- helper intentionally makes no local copies of the grid or washer tool.

workspace:WaitForChild("LocalDirtGridTest")
