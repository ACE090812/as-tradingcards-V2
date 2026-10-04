--[[ ---------------------------------------------------------------------------
    PLAYER CARD SHOP (job)
    Employees run the shop. While at least one is on duty the NPC shop and NPC trader step back.
    Hiring and firing is done by your framework (job grades), nothing is built for it here.

    Job and grades: set the framework JOB NAME and the grade LEVELS (numbers) that mean each rank.
    Everything is stored against the job, so stock and the till stay if the owner leaves.
--------------------------------------------------------------------------- ]]
Config.CardShop = {
    enabled = true,
    job = 'cardshop',
    grades = { staff = 0, manager = 2, owner = 4 },   -- minimum grade LEVEL for each rank
    -- ESX has no duty toggle: set true to treat everyone with the job as on duty
    esxAlwaysOnDuty = true,

    -- customer counter. SET these. Leave coords at 0 to use the NPC shop ped's spot.
    counter = { coords = vec3(0.0, 0.0, 0.0), radius = 1.6, blip = { sprite = 605, colour = 27, scale = 0.7, label = 'Football Cards' } },
    managerDesk = { coords = vec3(0.0, 0.0, 0.0), radius = 1.2 },   -- staff-only desk (leave 0 to use the counter)

    -- selling price limits (x market value). Stops money laundering through the shop.
    sellMin = 0.70, sellMax = 1.40,
    -- what the shop will pay players (x market value, the owner/managers choose inside the range)
    buyMin = 0.50, buyMax = 0.90, buyDefault = 0.60,

    -- staff pay
    pay = {
        hourly = 150,              -- per on-duty hour, paid out of the till
        every = 15,                -- minutes between pay-outs (hourly / 60 x every)
        commission = 0.05,         -- of each sale (and each grading fee), to the employee serving
        account = 'bank',          -- 'bank' | 'cash'
    },

    -- till (society account). 'auto' tries Renewed-Banking, qb-banking, okokBanking, qbx_management, esx_addonaccount.
    -- If none is found a built-in ledger in the database is used. See README > Card shop job.
    society = { resource = 'auto', account = 'cardshop' },

    -- who can do what
    withdraw = 'manager',          -- 'manager' = owner and managers, 'owner' = owner only
    wholesale = 'owner',

    -- wholesale order: the shop pays this share of the normal shop price. `items` empty = everything in Config.Shop.items
    wholesaleCatalogue = { pct = 0.70, maxPerItem = 200, items = {} },

    -- customers hand cards to staff for grading (the staff member submits). Fee goes to the till.
    grading = { enabled = true, nearby = 6.0 },

    -- ledger rows kept
    ledgerKeepDays = 60,
    -- someone ordering / buying with a stolen card is refused
    refuseStolen = true,
}
