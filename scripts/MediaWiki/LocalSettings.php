<?php
# Basic MediaWiki configuration for HHVM testing
$wgSitename = "TestWiki";
$wgMetaNamespace = "TestWiki";
$wgScriptPath = "";
$wgServer = "http://localhost:8080";
$wgResourceBasePath = $wgScriptPath;
$wgLogo = "$wgResourceBasePath/resources/assets/wiki.png";
$wgEnableEmail = false;
$wgEnableUserEmail = false;
$wgDBtype = "mysql";
$wgDBserver = "localhost:/tmp/mysql.sock";
$wgDBname = "mediawiki";
$wgDBuser = "wiki";
$wgDBpassword = "wiki123";
$wgDBprefix = "";
$wgDBTableOptions = "ENGINE=InnoDB, DEFAULT CHARSET=binary";
$wgSharedTables[] = "actor";
$wgMainCacheType = CACHE_ACCEL;
$wgMemCachedServers = [];
$wgEnableUploads = false;
$wgUseInstantCommons = false;
$wgPingback = false;
$wgLanguageCode = "en";
$wgLocaltimezone = "UTC";
$wgSecretKey = "a8f5f167f44f4964e6c998dee827110c";
$wgAuthenticationTokenVersion = "1";
$wgSiteNotice = "HHVM Benchmark Test";
