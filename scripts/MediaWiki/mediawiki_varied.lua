counter = 0
pages = {
    "/index.php?title=Main_Page",
    "/index.php?title=Special:Random",
    "/index.php?title=Special:RecentChanges",
    "/index.php?title=Special:AllPages",
    "/index.php?title=Help:Contents",
    "/api.php?action=query&list=random&rnlimit=10",
}
request = function()
    counter = counter + 1
    local path = pages[(counter % #pages) + 1]
    return wrk.format("GET", path)
end
