--[[ ---------------------------------------------------------------------------
    WANTLIST, THIS WEEK PAGE, RELEASE DAYS
--------------------------------------------------------------------------- ]]

-- Wantlist: players tap "Want" on cards; their phone pings when one is put up for auction
Config.Wants = {
    enabled = true,
    max = 50,                  -- cards per player
}

-- "This week" page: biggest sales, biggest pulls, movers
Config.Weekly = {
    enabled = true,
    showPullerNames = false,   -- false = pulls show as "J***n", true = the character's full name
}

-- Release days: a product goes on sale at a set time in the Card Market app / website, with a
-- limited number and a per-player limit. Bought items are sent to the buyer's Postal Prime locker
-- (or straight into their pockets without Postal Prime). Times are server time, 'YYYY-MM-DD HH:MM'.
-- `item` can be any shop item (a pack, box or tin). Add as many as you like; old ones can stay.
Config.Releases = {
    enabled = true,
    announce = true,           -- phone notification to everyone online when a release goes live
    list = {
        -- {
        --     id = 'hobby_launch',                  -- never change once it has sold
        --     label = 'Launch Day Box',
        --     description = 'The first hobby boxes of the season. 1 guaranteed hit in every box.',
        --     item = 'ascard_my_box',
        --     price = 450,
        --     quantity = 30,                        -- how many exist in total
        --     perPlayer = 2,                        -- how many one character can buy
        --     startsAt = '2026-10-02 19:00',
        --     endsAt = '2026-10-09 19:00',          -- optional
        -- },
    },
}
