'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callGetState = rpc.declare({ object: 'forkop.zapret', method: 'get_state', expect: { '': {} } });
var callGetSections = rpc.declare({ object: 'forkop.zapret', method: 'get_sections', expect: { '': {} } });
var callGetLog = rpc.declare({ object: 'forkop.zapret', method: 'get_log', params: [ 'offset' ], expect: { '': {} } });
var callSaveSection = rpc.declare({
	object: 'forkop.zapret',
	method: 'save_section_settings',
	params: [ 'section', 'enabled', 'strat_cats', 'all_combos', 'auto_apply', 'cron_schedule',
		'auto_update_time', 'auto_update_days',
		'dns_proto', 'dns_server', 'dns_servers', 'vpn_section', 'only_strat_update', 'disable_updates',
		'include_zm_domains', 'custom_strategy', 'follow_enabled', 'follow_from' ],
	expect: { '': {} }
});
var callStartTest = rpc.declare({ object: 'forkop.zapret', method: 'start_test', params: [ 'section', 'auto_apply', 'strat_cats', 'all_combos', 'include_zm_domains' ], expect: { '': {} } });
var callStopTest = rpc.declare({ object: 'forkop.zapret', method: 'stop_test', expect: { '': {} } });
var callApplyCustom = rpc.declare({
	object: 'forkop.zapret',
	method: 'apply_custom',
	params: [ 'sections', 'name', 'strategy', 'builder_state' ],
	expect: { '': {} }
});
var callCheckBlock = rpc.declare({ object: 'forkop.zapret', method: 'check_block', params: [ 'sections', 'domain' ], expect: { '': {} } });
var callCheckForkop = rpc.declare({ object: 'forkop.zapret', method: 'check_forkop', params: [ 'sections', 'domain' ], expect: { '': {} } });
var callGetCheckLog = rpc.declare({ object: 'forkop.zapret', method: 'get_check_log', params: [ 'offset' ], expect: { '': {} } });
var callStopCheck = rpc.declare({ object: 'forkop.zapret', method: 'stop_check', expect: { '': {} } });
var callUpdate = rpc.declare({ object: 'forkop.zapret', method: 'update', expect: { '': {} } });
var callGetUpdateLog = rpc.declare({ object: 'forkop.zapret', method: 'get_update_log', params: [ 'offset' ], expect: { '': {} } });
var callGetStrategies = rpc.declare({ object: 'forkop.zapret', method: 'get_strategies', params: [ 'refresh' ], expect: { '': {} } });

var PORTS_UDP = '88,1024-2407,2409-4499,4502-19293,19345-49999,50101-65535';
var PORTS_TCP = '2802,2302,2502,3478-3480,3724,6000-8000,8085,8090,8100,8903,8904,25565,27015-27030,27036-27037,35500-35600,50001,60442';

var CORE_PRESETS = [
	{ id: 'General_v11_Forkop_OneTrust', label: 'v11: Forkop Default (Multisplit 681/664 + MD5 + OneTrust)', args443: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=md5sig --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin', args80: '--filter-tcp=80,443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=664 --dpi-desync-split-pos=1 --dpi-desync-fooling=md5sig --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_onetrust_com.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/stun2.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_onetrust_com.bin --dpi-desync-fake-http=/opt/zapret/files/fake/tls_clienthello_www_onetrust_com.bin' },
	{ id: 'General_v1_Split2', label: 'v1: Split2 (seqovl 681 + stun.bin)', args443: '--filter-tcp=443 --dpi-desync=split2 --dpi-desync-split-seqovl=681 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin' },
	{ id: 'General_v2_Multisplit_MD5', label: 'v2: Fake + Multisplit (seqovl 681 + md5sig + Google SNI)', args443: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=md5sig --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' },
	{ id: 'General_v3_HostFake_Ozon', label: 'v3: HostFakeSplit (host=ozon.ru + md5sig)', args443: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=ozon.ru --dpi-desync-repeats=4 --dpi-desync-fooling=md5sig --dpi-desync-badseq-increment=0' },
	{ id: 'General_v4_Multisplit_582', label: 'v4: Multisplit (seqovl 582 + stun.bin)', args443: '--filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin' },
	{ id: 'General_v5_Disorder_Badseq', label: 'v5: Fake + FakedDisorder (badseq,badsum)', args443: '--filter-tcp=443 --dpi-desync=fake,fakeddisorder --dpi-desync-split-pos=1 --dpi-desync-fake-tls=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-tls-mod=none --dpi-desync-fakedsplit-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fooling=badseq,badsum --dpi-desync-badseq-increment=0' },
	{ id: 'General_v6_HostFake_2GIS', label: 'v6: HostFakeSplit (2gis.com + seqovl 726)', args443: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=i2.photo.2gis.com --dpi-desync-hostfakesplit-midhost=host-2 --dpi-desync-split-seqovl=726 --dpi-desync-fooling=badsum,badseq --dpi-desync-badseq-increment=0' },
	{ id: 'General_v7_Multisplit_654', label: 'v7: Fake + Multisplit (seqovl 654)', args443: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=654 --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq,badsum --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/stun.bin --dpi-desync-badseq-increment=0' },
	{ id: 'General_v8_Fake_4PDA', label: 'v8: Fake TLS (4pda.bin + md5sig)', args443: '--filter-tcp=443 --dpi-desync=fake --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=/opt/zapret/files/fake/4pda.bin --dpi-desync-fake-tls-mod=none' },
	{ id: 'General_v9_HostFake_Badsum', label: 'v9: HostFakeSplit (ozon.ru + badseq,badsum)', args443: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-fooling=badseq,badsum --dpi-desync-hostfakesplit-mod=host=ozon.ru --dpi-desync-badseq-increment=0' },
	{ id: 'General_v10_FakeSplit2_MaxCDN', label: 'v10: Fake + Split2 (maxcdn)', args443: '--filter-tcp=443 --dpi-desync=fake,split2 --dpi-desync-split-pos=2 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-hostfakesplit-mod=host=maxcdn.bootstrapcdn.com --dpi-desync-fake-tls-mod=rnd,sni=maxcdn.bootstrapcdn.com --dpi-desync-fooling=md5sig' },
	{ id: 'FakeTLS_SNIExt_679', label: 'FakeTLS: Multisplit (pos=2,sniext+1 + seqovl 679)', args443: '--filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-pos=2,sniext+1 --dpi-desync-split-seqovl=679 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'FakeTLS_Multidisorder_MidSLD', label: 'FakeTLS: Multidisorder (pos=1,midsld + badseq)', args443: '--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=badseq --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' },
	{ id: 'FakeTLS_HostFake_AltOrder', label: 'FakeTLS: HostFakeSplit (google.com,altorder=1)', args443: '--filter-tcp=443 --dpi-desync=fake,hostfakesplit --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com --dpi-desync-hostfakesplit-mod=host=www.google.com,altorder=1 --dpi-desync-fooling=md5sig' },
	{ id: 'FakeTLS_Google_MD5', label: 'FakeTLS: Fake + MD5 (Google SNI)', args443: '--filter-tcp=443 --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=none' },
	{ id: 'FakeTLS_Multisplit_Badseq1000', label: 'FakeTLS: Fake + Multisplit (badseq 1000)', args443: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=1000 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'FakeTLS_FakedSplit_Badseq2', label: 'FakeTLS: Fake + FakedSplit (badseq 2)', args443: '--filter-tcp=443 --dpi-desync=fake,fakedsplit --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --dpi-desync-repeats=8 --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' },
	{ id: 'FakeTLS_Multisplit_Badseq10M', label: 'FakeTLS: Fake + Multisplit (badseq 10M)', args443: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=10000000 --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' },
	{ id: 'FakeTLS_Pattern00_MD5', label: 'FakeTLS: Pattern 0x00 + MD5', args443: '--filter-tcp=443 --dpi-desync=fake,fakedsplit --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fakedsplit-pattern=0x00 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' }
];
var YT_PRESETS = [
	{ id: 'same', label: 'Использовать выбранное основное ядро TCP 443', args: '' },
	{ id: 'YouTube_Yv01', label: 'Yv01', args: '--filter-tcp=443 --ip-id=zero --dpi-desync=multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'YouTube_Yv02', label: 'Yv02', args: '--filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-pos=1,sniext+1 --dpi-desync-split-seqovl=1' },
	{ id: 'YouTube_Yv03', label: 'Yv03', args: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-pos=2,sld --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=ggpht.com --dpi-desync-split-seqovl=620 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fooling=badsum,badseq' },
	{ id: 'YouTube_Yv04', label: 'Yv04', args: '--filter-tcp=443 --dpi-desync=split2 --dpi-desync-split-seqovl=681 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'YouTube_Yv05', label: 'Yv05', args: '--filter-tcp=443 --dpi-desync=fake,fakeddisorder --dpi-desync-split-pos=10,midsld --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls-mod=none --dpi-desync-fakedsplit-pattern=/opt/zapret/files/fake/tls_clienthello_vk_com.bin --dpi-desync-split-seqovl=336 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_gosuslugi_ru.bin --dpi-desync-fooling=badseq,badsum --dpi-desync-badseq-increment=0' },
	{ id: 'YouTube_Yv06', label: 'Yv06', args: '--filter-tcp=443 --dpi-desync=multidisorder --dpi-desync-split-pos=7,sld+1 --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com --dpi-desync-fooling=badseq --dpi-desync-autottl 2:2-12' },
	{ id: 'YouTube_Yv07', label: 'Yv07', args: '--filter-tcp=443 --dpi-desync=multidisorder --dpi-desync-split-pos=1,midsld,endhost-1 --dpi-desync-repeats=2 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' },
	{ id: 'YouTube_Yv08', label: 'Yv08', args: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=google.com --dpi-desync-fooling=ts' },
	{ id: 'YouTube_Yv09', label: 'Yv09', args: '--filter-tcp=443 --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --dpi-desync=multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin' },
	{ id: 'YouTube_Yv10', label: 'Yv10', args: '--filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-pos=1,2 --dpi-desync-split-seqovl=4 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' },
	{ id: 'YouTube_Yv11', label: 'Yv11', args: '--filter-tcp=443 --dpi-desync=multidisorder --dpi-desync-split-pos=2,5,105,host+5,sld-1,endsld-5,endsld' },
	{ id: 'YouTube_Yv12', label: 'Yv12', args: '--filter-tcp=443 --dpi-desync=multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=2' },
	{ id: 'YouTube_Yv13', label: 'Yv13', args: '--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=10000000 --dpi-desync-repeats=2 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com' },
	{ id: 'YouTube_Yv14', label: 'Yv14', args: '--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=10,midsld --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com --dpi-desync-split-seqovl=336 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fooling=badseq' },
	{ id: 'YouTube_Yv15', label: 'Yv15', args: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-pos=2,sld --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=ggpht.com --dpi-desync-split-seqovl=2108 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fooling=badsum,badseq' },
	{ id: 'YouTube_Yv16', label: 'Yv16', args: '--filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-pos=1,sniext+1 --dpi-desync-split-seqovl=1 --dpi-desync-fooling=badsum,badseq --dpi-desync-badseq-increment=0' },
	{ id: 'YouTube_Yv17', label: 'Yv17', args: '--filter-tcp=443 --dpi-desync=fakeddisorder --dpi-desync-fooling=md5sig --dup=1 --dup-cutoff=n2 --dup-fooling=md5sig --dpi-desync-split-pos=method+2' },
	{ id: 'YouTube_Yv18', label: 'Yv18', args: '--filter-tcp=443 --ip-id=zero --dpi-desync=fake,hostfakesplit --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com --dpi-desync-hostfakesplit-mod=host=www.google.com,altorder=1 --dpi-desync-fooling=ts' },
	{ id: 'YouTube_Yv19', label: 'Yv19', args: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=! --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=2 --dpi-desync-fooling=badseq --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' },
	{ id: 'YouTube_Yv20', label: 'Yv20', args: '--filter-tcp=443 --ip-id=zero --dpi-desync=fake,fakedsplit --dpi-desync-repeats=6 --dpi-desync-fooling=ts --dpi-desync-fakedsplit-pattern=0x00 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'YouTube_Yv21', label: 'Yv21', args: '--filter-tcp=443 --ip-id=zero --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=ts --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'YouTube_Yv22', label: 'Yv22', args: '--filter-tcp=443 --dpi-desync=split2 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl=681 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin' },
	{ id: 'YouTube_Yv23', label: 'Yv23', args: '--filter-tcp=443 --dpi-desync=fake,fakeddisorder --dpi-desync-split-pos=1 --dpi-desync-fake-tls=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-tls-mod=none --dpi-desync-fakedsplit-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fooling=badseq,badsum --dpi-desync-badseq-increment=0' },
	{ id: 'YouTube_Yv24', label: 'Yv24', args: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=654 --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq,badsum --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/stun.bin --dpi-desync-badseq-increment=0' },
	{ id: 'YouTube_Yv25', label: 'Yv25', args: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-fooling=badseq,badsum --dpi-desync-hostfakesplit-mod=host=google.com --dpi-desync-badseq-increment=0' },
	{ id: 'YouTube_Yv26', label: 'Yv26', args: '--filter-tcp=443 --dpi-desync=multidisorder --dpi-desync-split-pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1' },
	{ id: 'YouTube_Yv27', label: 'Yv27', args: '--filter-tcp=443 --dpi-desync=multidisorder --dpi-desync-split-pos=1,2,3,5,105,host+5,sld-1,endsld-5,endsld --dpi-desync-fooling=badsum' },
	{ id: 'YouTube_Yv28', label: 'Yv28', args: '--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-seqovl=midsld-4 --dpi-desync-split-pos=2,midsld+3,sniext+2,endhost-2,midsld-3,host+1,-10 --dpi-desync-fooling=ts --dpi-desync-repeats=23 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_sferum_ru.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/stun2.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_sferum_ru.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-http=/opt/zapret/files/fake/tls_clienthello_max_ru.bin' },
	{ id: 'YouTube_Yv29', label: 'Yv29', args: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-fooling=ts --dpi-desync-hostfakesplit-mod=host=www.google.com --dpi-desync-hostfakesplit-midhost=midsld+1' },
	{ id: 'YouTube_Yv30', label: 'Yv30', args: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-fooling=ts --dpi-desync-hostfakesplit-mod=host=www.google.com --dpi-desync-hostfakesplit-midhost=sld+1' },
	{ id: 'YouTube_Yv31', label: 'Yv31', args: '--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=717 --dpi-desync-split-pos=sld,sld+3,endhost-1 --dpi-desync-fooling=ts --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com_2.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com_2.bin' },
	{ id: 'YouTube_Yv32', label: 'Yv32', args: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=ozon.ru --dpi-desync-repeats=4 --dpi-desync-fooling=ts,md5sig --dpi-desync-badseq-increment=0' },
	{ id: 'YouTube_Yv33', label: 'Yv33', args: '--filter-tcp=443 --filter-l7=tls --dpi-desync=multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-cutoff=s34229' },
	{ id: 'YouTube_Yv34', label: 'Yv34', args: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=google.com --dpi-desync-fooling=datanoack,badsum --dpi-desync-repeats=3' },
	{ id: 'YouTube_Yv35', label: 'Yv35', args: '--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=google.com --dpi-desync-fooling=badseq,badsum --dpi-desync-badseq-increment=0 --dpi-desync-repeats=3' },
];
var DISC_TCP_PRESETS = [
	{ id: 'Discord_Dv_MD5', label: 'Dv_MD5: Fake + Multisplit (seqovl 681 + md5sig)', args: '--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=md5sig --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'Discord_Dv1_Split652', label: 'Dv1: Multisplit (seqovl 652)', args: '--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=multisplit --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'Discord_Dv5_Badseq1000', label: 'Dv5: Fake + Multisplit (badseq 1000)', args: '--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=fake,multisplit --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=1000 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'Discord_Dv7_SNIExt679', label: 'Dv7: Multisplit (sniext+1)', args: '--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=multisplit --dpi-desync-split-pos=2,sniext+1 --dpi-desync-split-seqovl=679 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin' },
	{ id: 'Discord_Dv9_FakedSplit', label: 'Dv9: Fake + FakedSplit (badseq 2)', args: '--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=fake,fakedsplit --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --dpi-desync-repeats=8 --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' },
	{ id: 'Discord_Dv15_Multidisorder', label: 'Dv15: Fake + Multidisorder', args: '--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=badseq --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com' }
];
var DISC_FAKE_BINS = [
	{ id: 'quic_initial_steamcommunity_com.bin', label: 'quic_initial_steamcommunity_com.bin' },
	{ id: 'stun.bin', label: 'stun.bin' },
	{ id: 'stun2.bin', label: 'stun2.bin' },
	{ id: 'quic_initial_4pda_to.bin', label: 'quic_initial_4pda_to.bin' },
	{ id: 'quic_initial_tencent_com.bin', label: 'quic_initial_tencent_com.bin' },
	{ id: 'tls_clienthello_sochi_park.bin', label: 'tls_clienthello_sochi_park.bin' },
	{ id: 'quic_initial_5ka_ru.bin', label: 'quic_initial_5ka_ru.bin' },
	{ id: 'quic_initial_rutube_ru.bin', label: 'quic_initial_rutube_ru.bin' }
];
var GAME_PRESETS = [
	{ id: 'Game_Gv1_Cutoff_d2', label: 'Gv1: Cutoff d2 + Fake UDP + Multisplit TCP', udp: '--filter-udp=' + PORTS_UDP + ' --dpi-desync=fake --dpi-desync-cutoff=d2 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin' },
	{ id: 'Game_Gv2_Cutoff_n2', label: 'Gv2: Cutoff n2 + Repeats 10', udp: '--filter-udp=' + PORTS_UDP + ' --dpi-desync=fake --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin --dpi-desync-cutoff=n2' },
	{ id: 'Game_Gv3_Cutoff_n3', label: 'Gv3: Cutoff n3', udp: '--filter-udp=' + PORTS_UDP + ' --dpi-desync=fake --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin --dpi-desync-cutoff=n3' },
	{ id: 'Game_Gv4_Cutoff_n4', label: 'Gv4: Cutoff n4', udp: '--filter-udp=' + PORTS_UDP + ' --dpi-desync=fake --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin --dpi-desync-cutoff=n4' },
	{ id: 'off', label: 'Отключено', udp: '' }
];

var shortCode = function(id) {
	var m;
	if ((m = id.match(/^General_v(\d+)/))) return 'G' + m[1];
	if (id === 'FakeTLS_SNIExt_679') return 'FT1';
	if (id === 'FakeTLS_Multidisorder_MidSLD') return 'FT2';
	if (id === 'FakeTLS_HostFake_AltOrder') return 'FT3';
	if (id === 'FakeTLS_Google_MD5') return 'FT4';
	if (id === 'FakeTLS_Multisplit_Badseq1000') return 'FT5';
	if (id === 'FakeTLS_FakedSplit_Badseq2') return 'FT6';
	if (id === 'FakeTLS_Multisplit_Badseq10M') return 'FT7';
	if (id === 'FakeTLS_Pattern00_MD5') return 'FT8';
	if (id === 'Discord_Dv_MD5') return 'D0';
	if ((m = id.match(/^Discord_Dv(\d+)/))) return 'D' + m[1];
	if ((m = id.match(/^YouTube_gVideo(\d+)/))) return 'VID' + m[1];
	if ((m = id.match(/^YouTube_Yv0*(\d+)/))) return 'YT' + m[1];
	if ((m = id.match(/^Game_Gv(\d+)/))) return 'GV' + m[1];
	return id;
};
var makeOpts = function(arr, curVal) {
	return arr.map(function(item) {
		var sc = shortCode(item.id);
		var label = (sc !== item.id) ? (sc + ': ' + item.label) : item.label;
		return E('option', { 'value': item.id, 'selected': (curVal === item.id) ? 'selected' : null }, label);
	});
};

return view.extend({
	logOffset: 0,
	checkOffset: 0,
	checkRunning: false,
	isRunning: false,
	startGraceUntil: 0,
	activeTab: 'auto',
	selectedSection: '',
	state: {},

	load: function() {
		var self = this;
		return callGetState().then(function(s) { self.state = s; return s; });
	},

	sectionList: function() {
		return (this.state && this.state.sections) ? this.state.sections : [];
	},
	sectionById: function(id) {
		var list = this.sectionList();
		for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
		return null;
	},
	settingsOf: function(id) {
		var ss = (this.state && this.state.section_settings) ? this.state.section_settings : {};
		return ss[id] || {};
	},
	defaultSection: function() {
		var list = this.sectionList();
		for (var i = 0; i < list.length; i++) if (list[i].is_zapret) return list[i].id;
		return list.length ? list[0].id : '';
	},

	selectSection: function(id) {
		this.selectedSection = id;
		var s = this.settingsOf(id);
		var sec = this.sectionById(id) || {};
		var cats = (s.strat_cats || 'general,faketls,youtube,discord,gv').split(',');
		['general', 'faketls', 'youtube', 'discord', 'gv'].forEach(function(c) {
			var el = document.getElementById('fz-cat-' + c);
			if (el) el.checked = cats.indexOf(c) !== -1;
		});
		var setVal = function(i, v) { var e = document.getElementById(i); if (e) e.value = v; };
		var setChk = function(i, b) { var e = document.getElementById(i); if (e) e.checked = !!b; };
		setChk('fz-all-combos', s.all_combos === '1');
		setChk('fz-auto-apply', s.auto_apply !== '0');
		setVal('fz-cron-sched', s.cron_schedule || 'off');
		setVal('fz-auto-time', s.auto_update_time || '03:00');
		setVal('fz-auto-days', s.auto_update_days || '*');
		setVal('fz-dns-proto', s.dns_proto || 'doh');
		setVal('fz-dns-server', s.dns_server || '8.8.8.8');
		setVal('fz-vpn-sec', s.vpn_section || 'none');
		setChk('fz-only-strat', s.only_strat_update !== '0');
		setChk('fz-dis-updates', s.disable_updates === '1');
		setChk('fz-inc-zm', s.include_zm_domains === '1');
		setVal('fz-custom-strat', s.custom_strategy || '');
		var role = document.getElementById('fz-sec-role');
		if (role) role.textContent = sec.is_zapret ? '⚡ zapret-секция (стратегии применяются)' : '🛡️ не zapret (только домены/маршрут)';
		var fb = document.getElementById('fz-follow-box');
		if (fb) fb.style.display = sec.is_zapret ? 'flex' : 'none';
		var fe = document.getElementById('fz-follow-en');
		if (fe) fe.checked = (s.follow_enabled === '1');
		var fs = document.getElementById('fz-follow-from');
		if (fs) {
			while (fs.firstChild) fs.removeChild(fs.firstChild);
			var opts = this.sectionList().filter(function(x) { return x.is_zapret && x.id !== id; });
			if (!opts.length) {
				fs.appendChild(E('option', { value: '' }, '— нет других zapret-секций —'));
			} else {
				opts.forEach(function(x) {
					fs.appendChild(E('option', { value: x.id, selected: (s.follow_from === x.id) ? 'selected' : null }, x.label ? (x.label + ' (' + x.id + ')') : x.id));
				});
			}
		}
		this.toggleFollowMode();
		var ds = document.getElementById('fz-dns-rows');
		if (ds) {
			while (ds.firstChild) ds.removeChild(ds.firstChild);
			var selfSec = this;
			var list = (s.dns_servers || '').split(';').filter(Boolean);
			if (!list.length) list = [(s.dns_proto || 'doh') + '|' + (s.dns_server || '8.8.8.8')];
			list.forEach(function(e) { ds.appendChild(selfSec.dnsRow(e)); });
		}
		var ss = (this.state.section_strategies || {})[id] || {};
		var best = document.getElementById('fz-best-box');
		if (best) {
			var name = ss.best_strategy || this.state.best_strategy || '';
			best.textContent = name ? ('★ Сохранённая стратегия секции: ' + name) : 'Стратегия для этой секции ещё не подобрана';
		}
	},

	toggleFollowMode: function() {
		var fe = document.getElementById('fz-follow-en');
		var fb = document.getElementById('fz-follow-box');
		var on = fe && fe.checked && (!fb || fb.style.display !== 'none');
		var btns = document.getElementById('fz-tab-buttons');
		if (btns) btns.style.display = on ? 'none' : 'flex';
		var note = document.getElementById('fz-follow-note');
		if (note) note.style.display = on ? 'block' : 'none';
		if (on) {
			['auto', 'builder', 'settings'].forEach(function(t) {
				var p = document.getElementById('fz-tab-' + t);
				if (p) p.style.display = 'none';
			});
		} else {
			this.switchTab(this.activeTab);
		}
	},

	dnsRow: function(entry) {
		var parts = (entry || 'doh|').split('|');
		var proto = parts[0] || 'doh';
		var addr = parts[1] || '';
		var sel = E('select', { 'class': 'cbi-input-select fz-dns-proto', 'style': 'width:120px;' }, [
			E('option', { 'value': 'doh', 'selected': proto === 'doh' ? 'selected' : null }, 'DoH'),
			E('option', { 'value': 'dot', 'selected': proto === 'dot' ? 'selected' : null }, 'DoT'),
			E('option', { 'value': 'udp', 'selected': proto === 'udp' ? 'selected' : null }, 'UDP')
		]);
		var inp = E('input', { 'type': 'text', 'class': 'cbi-input-text fz-dns-addr', 'style': 'flex:1;', 'value': addr, 'placeholder': '8.8.8.8 или https://...' });
		var row = E('div', { 'class': 'fz-dns-row', 'style': 'display:flex; gap:8px; align-items:center;' }, [ sel, inp ]);
		row.appendChild(E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': function() { row.remove(); } }, '✕'));
		return row;
	},
	addDnsRow: function() {
		var ds = document.getElementById('fz-dns-rows');
		if (ds) ds.appendChild(this.dnsRow('doh|'));
	},

	readSectionForm: function() {
		var cats = [];
		['general', 'faketls', 'youtube', 'discord', 'gv'].forEach(function(c) {
			var el = document.getElementById('fz-cat-' + c);
			if (el && el.checked) cats.push(c);
		});
		var val = function(i) { var e = document.getElementById(i); return e ? e.value : ''; };
		var chk = function(i) { var e = document.getElementById(i); return e ? (e.checked ? '1' : '0') : '0'; };
		var sec = this.sectionById(this.selectedSection) || {};
		var dnsRows = [];
		document.querySelectorAll('.fz-dns-row').forEach(function(row) {
			var p = row.querySelector('.fz-dns-proto');
			var a = row.querySelector('.fz-dns-addr');
			if (p && a && a.value.trim()) dnsRows.push(p.value + '|' + a.value.trim());
		});
		var firstDns = dnsRows.length ? dnsRows[0].split('|') : ['doh', '8.8.8.8'];
		return {
			section: this.selectedSection,
			enabled: '1',
			strat_cats: cats.join(','),
			all_combos: chk('fz-all-combos'),
			auto_apply: chk('fz-auto-apply'),
			cron_schedule: val('fz-cron-sched'),
			auto_update_time: val('fz-auto-time') || '03:00',
			auto_update_days: val('fz-auto-days') || '*',
			dns_proto: firstDns[0],
			dns_server: firstDns[1],
			dns_servers: dnsRows.join(';'),
			vpn_section: val('fz-vpn-sec'),
			only_strat_update: chk('fz-only-strat'),
			disable_updates: chk('fz-dis-updates'),
			include_zm_domains: chk('fz-inc-zm'),
			custom_strategy: val('fz-custom-strat'),
			follow_enabled: sec.is_zapret ? chk('fz-follow-en') : '0',
			follow_from: sec.is_zapret ? val('fz-follow-from') : ''
		};
	},

	doSaveSection: function() {
		var f = this.readSectionForm();
		if (!f.section) return Promise.reject(new Error('Выберите секцию'));
		return callSaveSection(f.section, f.enabled, f.strat_cats, f.all_combos, f.auto_apply, f.cron_schedule,
			f.auto_update_time, f.auto_update_days,
			f.dns_proto, f.dns_server, f.dns_servers, f.vpn_section, f.only_strat_update, f.disable_updates,
			f.include_zm_domains, f.custom_strategy, f.follow_enabled, f.follow_from);
	},
	saveAutoSettings: function() {
		if (!this.selectedSection) return;
		return this.doSaveSection().catch(function() {});
	},

	handleSaveSection: function() {
		return this.doSaveSection().then(function() {
			ui.addNotification(null, E('p', 'Настройки секции сохранены.'), 'info');
		}).catch(function(err) { ui.addNotification(null, E('p', 'Ошибка: ' + err.message), 'error'); });
	},
	handleRefreshStrategies: function() {
		var self = this;
		return callGetStrategies('1').then(function(res) {
			var gen = (res.general || []).map(function(x) { return { id: x.id, label: x.id, args443: x.body, args80: (x.body || '').replace('--filter-tcp=443', '--filter-tcp=80,443') }; });
			var ft = (res.faketls || []).map(function(x) { return { id: x.id, label: x.id, args443: x.body, args80: (x.body || '').replace('--filter-tcp=443', '--filter-tcp=80,443') }; });
			CORE_PRESETS = gen.concat(ft);
			YT_PRESETS = [{ id: 'same', label: 'Использовать выбранное основное ядро TCP 443', args: '' }].concat((res.youtube || []).map(function(x) { return { id: x.id, label: x.id, args: x.body }; }));
			DISC_TCP_PRESETS = (res.discord || []).map(function(x) { return { id: x.id, label: x.id, args: x.body }; });
			GAME_PRESETS = (res.gv || []).map(function(x) { return { id: x.id, label: x.id, udp: x.body }; }).concat([{ id: 'off', label: 'Отключено', udp: '' }]);
			self.refillBuilder();
			self.updateBuilderPreview();
			ui.addNotification(null, E('p', 'Стратегии обновлены: General ' + gen.length + ', FakeTLS ' + ft.length + ', YouTube ' + (res.youtube || []).length + ', Discord ' + (res.discord || []).length + ', Game ' + (res.gv || []).length), 'info');
		}).catch(function(err) { ui.addNotification(null, E('p', 'Ошибка обновления стратегий: ' + err.message), 'error'); });
	},
	refillBuilder: function() {
		var fill = function(id, arr, cur) {
			var el = document.getElementById(id);
			if (!el) return;
			var keep = el.value || cur;
			while (el.firstChild) el.removeChild(el.firstChild);
			arr.forEach(function(item) {
				var sc = shortCode(item.id);
				var label = (sc !== item.id) ? (sc + ': ' + item.label) : item.label;
				el.appendChild(E('option', { 'value': item.id, 'selected': (item.id === keep) ? 'selected' : null }, label));
			});
		};
		fill('fz-bld-core', CORE_PRESETS, 'General_v11_Forkop_OneTrust');
		fill('fz-bld-yt', YT_PRESETS, 'same');
		fill('fz-bld-disctcp', DISC_TCP_PRESETS, 'Discord_Dv_MD5');
		fill('fz-bld-game', GAME_PRESETS, 'Game_Gv1_Cutoff_d2');
	},
	handleUpdateAddon: function() {
		var self = this;
		var con = document.getElementById('fz-update-console');
		if (con) { con.style.display = 'block'; con.textContent = ''; }
		if (this.updatePoll) clearInterval(this.updatePoll);
		this.updateLogOffset = 0;
		this.updatePoll = setInterval(function() {
			callGetUpdateLog(self.updateLogOffset).then(function(r) {
				if (!r) return;
				if (r.log_chunk && con) { con.textContent += r.log_chunk; con.scrollTop = con.scrollHeight; }
				if (typeof r.next_offset === 'number') self.updateLogOffset = r.next_offset;
				if (r.log_chunk && r.log_chunk.indexOf('Обновление завершено') !== -1) {
					clearInterval(self.updatePoll);
					ui.addNotification(null, E('p', 'Аддон обновлён. Настройки сохранены.'), 'info');
				} else if (r.log_chunk && r.log_chunk.indexOf('Ошибка') !== -1) {
					clearInterval(self.updatePoll);
					ui.addNotification(null, E('p', 'Обновление завершилось с ошибкой (см. консоль).'), 'error');
				}
			});
		}, 700);
		return callUpdate().then(function(res) {
			if (!res || !res.ok) {
				clearInterval(self.updatePoll);
				ui.addNotification(null, E('p', 'Ошибка запуска обновления: ' + ((res && res.error) || 'неизвестно')), 'error');
			}
		}).catch(function(err) {
			clearInterval(self.updatePoll);
			ui.addNotification(null, E('p', 'Ошибка: ' + err.message), 'error');
		});
	},

	getCheckSections: function() {
		var checked = [];
		document.querySelectorAll('.fz-chk-sec-cb:checked').forEach(function(cb) { checked.push(cb.value); });
		return checked.join(',');
	},
	createCheckLine: function(raw) {
		var type = 'info';
		if (raw.indexOf('[BLOCK_OK]') !== -1) type = 'ok';
		else if (raw.indexOf('[BLOCK_DNS]') !== -1) type = 'dns';
		else if (raw.indexOf('[BLOCK_IP]') !== -1) type = 'ip';
		else if (raw.indexOf('[BLOCK_DPI]') !== -1) type = 'dpi';
		else if (raw.indexOf('[FORKOP_OK]') !== -1) type = 'forkop';
		else if (raw.indexOf('[FORKOP_FAIL]') !== -1) type = 'forkop';
		else if (raw.indexOf('[FORKOP_DNS]') !== -1) type = 'forkop';
		var clean = raw.replace(/\[(BLOCK_OK|BLOCK_DNS|BLOCK_IP|BLOCK_DPI|FORKOP_OK|FORKOP_FAIL|FORKOP_DNS|INFO|ERR|DONE|WARN)\]\s*/, '');
		var style = 'font-family:monospace; font-size:12px; white-space:pre-wrap; padding:1px 0; ';
		if (type === 'ok') style += 'color:#4ade80;';
		else if (type === 'dns') style += 'color:#94a3b8;';
		else if (type === 'ip') style += 'color:#f87171;';
		else if (type === 'dpi') style += 'color:#fb923c;';
		else if (type === 'forkop') style += 'color:#38bdf8;';
		else style += 'color:#cbd5e1;';
		return E('div', { 'data-type': type, 'style': style }, clean);
	},
	appendCheckLog: function(chunk) {
		var con = document.getElementById('fz-chk-console');
		if (!con || !chunk) return;
		if (con.getAttribute('data-empty') === '1') { con.innerHTML = ''; con.setAttribute('data-empty', '0'); }
		var self = this;
		chunk.split('\n').forEach(function(line) { if (line.trim()) con.appendChild(self.createCheckLine(line)); });
		this.applyCheckFilters();
		con.scrollTop = con.scrollHeight;
	},
	applyCheckFilters: function() {
		var map = { ok: 'fz-chk-f-ok', dns: 'fz-chk-f-dns', ip: 'fz-chk-f-ip', dpi: 'fz-chk-f-dpi' };
		var con = document.getElementById('fz-chk-console');
		if (!con) return;
		var nodes = con.querySelectorAll('[data-type]');
		for (var i = 0; i < nodes.length; i++) {
			var t = nodes[i].getAttribute('data-type');
			var el = map[t] ? document.getElementById(map[t]) : null;
			nodes[i].style.display = el && !el.checked ? 'none' : '';
		}
	},
	startCheckPolling: function() {
		var self = this;
		poll.add(function() {
			return callGetCheckLog(self.checkOffset).then(function(res) {
				if (res.log_chunk) self.appendCheckLog(res.log_chunk);
				if (typeof res.next_offset === 'number') self.checkOffset = res.next_offset;
				self.checkRunning = !!res.running;
				var b = document.getElementById('fz-chk-status');
				if (b) { b.textContent = res.running ? 'ВЫПОЛНЯЕТСЯ' : 'ОЖИДАНИЕ'; b.style.background = res.running ? '#2563eb' : '#4b5563'; }
			});
		}, 1);
	},
	runCheck: function(kind, domain) {
		domain = (domain || '').trim();
		var secs = this.getCheckSections();
		if (!domain && !secs) { ui.addNotification(null, E('p', 'Отметьте секцию или введите домен.'), 'warning'); return; }
		var con = document.getElementById('fz-chk-console');
		if (con) { con.innerHTML = ''; con.setAttribute('data-empty', '0'); }
		this.checkOffset = 0;
		var b = document.getElementById('fz-chk-status');
		if (b) { b.textContent = 'ВЫПОЛНЯЕТСЯ'; b.style.background = '#2563eb'; }
		return kind === 'forkop' ? callCheckForkop(secs, domain) : callCheckBlock(secs, domain);
	},
	runSingleCheck: function(kind) {
		var d = (document.getElementById('fz-chk-domain') || {}).value || '';
		d = d.trim();
		if (!d) { ui.addNotification(null, E('p', 'Введите домен.'), 'warning'); return; }
		return this.runCheck(kind, d);
	},
	handleStopCheck: function() {
		return callStopCheck().then(function() {
			ui.addNotification(null, E('p', 'Проверка остановлена.'), 'info');
		});
	},
	handleCheckBlock: function() { return this.runCheck('block'); },
	handleCheckForkop: function() { return this.runCheck('forkop'); },

	updateBuilderPreview: function() {
		var coreEl = document.getElementById('fz-bld-core');
		var ytEl = document.getElementById('fz-bld-yt');
		var discTcpEl = document.getElementById('fz-bld-disctcp');
		var discBinEl = document.getElementById('fz-bld-discbin');
		var gameEl = document.getElementById('fz-bld-game');
		var previewEl = document.getElementById('fz-bld-preview');
		if (!coreEl || !previewEl) return;
		var coreObj = CORE_PRESETS.find(function(x) { return x.id === coreEl.value; }) || CORE_PRESETS[0];
		var ytObj = YT_PRESETS.find(function(x) { return x.id === (ytEl ? ytEl.value : 'same'); }) || YT_PRESETS[0];
		var discObj = DISC_TCP_PRESETS.find(function(x) { return x.id === (discTcpEl ? discTcpEl.value : 'Discord_Dv_MD5'); }) || DISC_TCP_PRESETS[0];
		var discBin = discBinEl ? discBinEl.value : 'quic_initial_steamcommunity_com.bin';
		var gameObj = GAME_PRESETS.find(function(x) { return x.id === (gameEl ? gameEl.value : 'Game_Gv1_Cutoff_d2'); }) || GAME_PRESETS[0];

		var parts = [];
		parts.push('--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-fake-discord=/opt/zapret/files/fake/' + discBin + ' --dpi-desync-fake-stun=/opt/zapret/files/fake/' + discBin + ' --dpi-desync-repeats=6');
		parts.push(discObj.args);
		parts.push(ytObj.args ? ytObj.args : coreObj.args443);
		parts.push(coreObj.args80 ? coreObj.args80 : coreObj.args443.replace(/^--filter-tcp=443/, '--filter-tcp=80,443'));
		if (gameObj.udp) {
			parts.push(gameObj.udp);
			parts.push('--filter-tcp=' + PORTS_TCP + ' --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n5 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin');
		}
		previewEl.value = parts.join(' --new ');
	},

	handleApplyCustom: function() {
		var sec = this.selectedSection;
		if (!sec) { ui.addNotification(null, E('p', 'Выберите секцию'), 'warning'); return; }
		var strat = (document.getElementById('fz-bld-preview') || {}).value || '';
		if (!strat.trim()) return;
		var coreId = (document.getElementById('fz-bld-core') || {}).value || 'Custom';
		return callApplyCustom(sec, 'Custom_' + coreId, strat.trim(), '').then(function() {
			ui.addNotification(null, E('p', 'Собранная стратегия применена в ' + sec + '.'), 'info');
		}).catch(function(err) { ui.addNotification(null, E('p', 'Ошибка: ' + err.message), 'error'); });
	},

	updateProgressFromLog: function(chunk) {
		if (!chunk) return;
		var m = chunk.match(/\[\s*(\d+)%\]/g);
		if (m && m.length) {
			var pct = parseInt(m[m.length - 1].replace(/\D/g, ''), 10);
			var bar = document.getElementById('fz-progress-bar');
			var lbl = document.getElementById('fz-progress-label');
			if (bar && !isNaN(pct)) { bar.style.width = pct + '%'; if (lbl) lbl.textContent = pct + '%'; }
		}
		var bestMatch = chunk.match(/ПОБЕДИТЕЛЬ[^:]*:\s*\[([^\]]+)\]/) || chunk.match(/ПОБЕДИТЕЛЬ ПОДБОРА:\s*\[([^\]]+)\]/);
		if (bestMatch && bestMatch[1]) {
			var b = document.getElementById('fz-best-box');
			if (b) b.textContent = '★ Сохранённая стратегия секции: ' + bestMatch[1];
		}
	},

	copyStrategyText: function(text, btn) {
		if (!text) return;
		var done = function() { btn.textContent = '✓ Скопировано!'; setTimeout(function() { btn.textContent = '📋 Скопировать'; }, 2000); };
		if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done);
		else {
			var ta = document.createElement('textarea'); ta.value = text; document.body.appendChild(ta); ta.select();
			document.execCommand('copy'); document.body.removeChild(ta); done();
		}
	},

	createColoredLogLine: function(rawLine) {
		var self = this;
		var style = 'padding:2px 6px; margin:1px 0; border-radius:4px; font-family:monospace; font-size:13px; white-space:pre-wrap;';
		if (rawLine.indexOf('[COPY_BOX]') !== -1) {
			var pure = rawLine.replace(/^.*?\[COPY_BOX\]\s*/, '').trim();
			var copyBtn = E('button', { 'class': 'btn cbi-button cbi-button-apply', 'style': 'margin-bottom:8px; padding:4px 12px; font-size:12px;', 'click': function() { self.copyStrategyText(pure, copyBtn); } }, '📋 Скопировать');
			var codeBox = E('div', { 'style': 'background:#020617; color:#fde047; padding:12px; border:1px dashed #eab308; border-radius:6px; font-family:monospace; font-size:12px; line-height:1.5; word-break:break-all; user-select:all;', 'click': function() {
				var range = document.createRange(); range.selectNodeContents(codeBox);
				var sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
			}}, pure);
			return E('div', { 'style': 'margin:14px 0; padding:14px; background:rgba(234,179,8,0.12); border:2px solid #eab308; border-radius:8px;' }, [
				E('div', { 'style': 'display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;' }, [
					E('span', { 'style': 'color:#fef08a; font-weight:bold; font-size:13px;' }, 'Стратегия для вставки:'),
					copyBtn
				]),
				codeBox
			]);
		}
		var clean = rawLine.replace(/\[(STAGE|INFO|SEC_OK|SEC_FAIL|ZM_OK|ZM_FAIL|TSPU_WARN|RESULT|BEST|COPY_HEAD|WARN|ERR)\]\s*/, '');
		if (rawLine.indexOf('[STAGE]') !== -1) style += 'color:#38bdf8; font-weight:bold; background:rgba(56,189,248,0.12); border-left:3px solid #38bdf8; margin-top:6px;';
		else if (rawLine.indexOf('[SEC_OK]') !== -1) style += 'color:#e879f9; font-weight:bold; background:rgba(232,121,249,0.12); border-left:3px solid #d946ef;';
		else if (rawLine.indexOf('[SEC_FAIL]') !== -1) style += 'color:#fb7185; font-weight:bold; background:rgba(251,113,133,0.12); border-left:3px solid #f43f5e;';
		else if (rawLine.indexOf('[TSPU_WARN]') !== -1) style += 'color:#fb923c; font-weight:bold; background:rgba(251,146,60,0.15); border-left:3px solid #f97316;';
		else if (rawLine.indexOf('[ZM_OK]') !== -1) style += 'color:#34d399;';
		else if (rawLine.indexOf('[ZM_FAIL]') !== -1) style += 'color:#6b7280;';
		else if (rawLine.indexOf('[RESULT]') !== -1) style += 'color:#fbbf24; font-weight:bold; background:rgba(251,191,36,0.14); border:1px solid rgba(251,191,36,0.4); margin:4px 0;';
		else if (rawLine.indexOf('[BEST]') !== -1) style += 'color:#4ade80; font-weight:bold; font-size:14px; background:rgba(74,222,128,0.18); border:1px solid #22c55e; padding:6px 8px; margin:6px 0;';
		else if (rawLine.indexOf('[COPY_HEAD]') !== -1) style += 'color:#fde047; font-weight:bold; font-size:13px; margin-top:12px; border-top:1px solid #475569; padding-top:10px;';
		else if (rawLine.indexOf('[WARN]') !== -1) style += 'color:#facc15; font-weight:bold;';
		else if (rawLine.indexOf('[ERR]') !== -1) style += 'color:#f87171; font-weight:bold; background:rgba(248,113,113,0.15); border-left:3px solid #ef4444;';
		else style += 'color:#cbd5e1;';
		return E('div', { 'style': style }, clean);
	},

	appendLogText: function(chunk) {
		var con = document.getElementById('fz-console');
		if (!con || !chunk) return;
		if (con.getAttribute('data-empty') === '1') { con.innerHTML = ''; con.setAttribute('data-empty', '0'); }
		var self = this;
		chunk.split('\n').forEach(function(line) { if (line.trim()) con.appendChild(self.createColoredLogLine(line)); });
		var auto = document.getElementById('fz-autoscroll');
		if (!auto || auto.checked) con.scrollTop = con.scrollHeight;
		this.updateProgressFromLog(chunk);
	},

	setRunningUI: function(running) {
		this.isRunning = running;
		var b = document.getElementById('fz-btn-start');
		var s = document.getElementById('fz-status-badge');
		if (b) b.disabled = running;
		if (s) { s.textContent = running ? 'ВЫПОЛНЯЕТСЯ ПОДБОР' : 'ОЖИДАНИЕ'; s.style.background = running ? '#2563eb' : '#4b5563'; }
	},

	startPolling: function() {
		var self = this;
		poll.add(function() {
			return callGetLog(self.logOffset).then(function(res) {
				if (res.log_chunk) self.appendLogText(res.log_chunk);
				if (typeof res.next_offset === 'number') self.logOffset = res.next_offset;
				if (Date.now() < self.startGraceUntil && !res.running) return;
				self.setRunningUI(!!res.running);
			});
		}, 1);
	},

	switchTab: function(tabName) {
		this.activeTab = tabName;
		var tabs = ['auto', 'builder', 'check', 'settings'];
		tabs.forEach(function(t) {
			var pane = document.getElementById('fz-tab-' + t);
			var btn = document.getElementById('fz-tabbtn-' + t);
			if (pane) pane.style.display = (t === tabName) ? 'block' : 'none';
			if (btn) {
				btn.style.background = (t === tabName) ? '#2563eb' : '#1f2937';
				btn.style.borderColor = (t === tabName) ? '#3b82f6' : '#374151';
			}
		});
		if (tabName === 'builder') this.updateBuilderPreview();
	},

	handleStart: function() {
		var self = this;
		var f = this.readSectionForm();
		if (!f.section) { ui.addNotification(null, E('p', 'Выберите секцию.'), 'warning'); return; }
		var con = document.getElementById('fz-console');
		if (con) { con.innerHTML = ''; con.setAttribute('data-empty', '0'); }
		this.logOffset = 0;
		this.startGraceUntil = Date.now() + 4000;
		var bar = document.getElementById('fz-progress-bar');
		var lbl = document.getElementById('fz-progress-label');
		if (bar) bar.style.width = '1%';
		if (lbl) lbl.textContent = '1%';
		this.setRunningUI(true);
		var startBtn = document.getElementById('fz-btn-start');
		if (startBtn) startBtn.textContent = '⏳ Запуск...';
		return this.doSaveSection().then(function() {
			return new Promise(function(resolve) {
				setTimeout(function() {
					if (startBtn) startBtn.textContent = '▶ Запустить подбор';
					resolve(callStartTest(f.section, f.auto_apply, f.strat_cats, f.all_combos, f.include_zm_domains));
				}, 800);
			});
		}).catch(function(err) { ui.addNotification(null, E('p', 'Ошибка: ' + err.message), 'error'); });
	},

	handleStop: function() {
		var self = this;
		self.startGraceUntil = 0;
		var btn = document.getElementById('fz-btn-stop');
		if (btn) btn.textContent = '⏳ Остановка...';
		return callStopTest().then(function() {
			self.setRunningUI(false);
			if (btn) btn.textContent = '■ Остановить';
		});
	},

	handleRefreshSections: function() {
		window.location.reload();
	},

	checkSectionsChanged: function() {
		var self = this;
		return callGetSections().then(function(res) {
			var ids = (res.sections || []).map(function(s) { return s.id + ':' + (s.label || '') + ':' + (s.is_zapret ? 1 : 0); }).sort().join(',');
			var cur = self.sectionList().map(function(s) { return s.id + ':' + (s.label || '') + ':' + (s.is_zapret ? 1 : 0); }).sort().join(',');
			if (ids !== cur) window.location.reload();
		}).catch(function() {});
	},

	render: function(state) {
		var self = this;
		this.state = state;
		if (!this.selectedSection) this.selectedSection = this.defaultSection();
		var sel = this.settingsOf(this.selectedSection);
		var sec = this.sectionById(this.selectedSection) || {};
		var savedCats = (sel.strat_cats || 'general,faketls,youtube,discord,gv').split(',').filter(Boolean);

		var secSelect = E('select', { id: 'fz-sec-select', 'class': 'cbi-input-select', 'style': 'width:320px;', 'change': function(ev) { self.selectSection(ev.target.value); } },
			this.sectionList().map(function(s) {
				return E('option', { 'value': s.id, 'selected': (s.id === self.selectedSection) ? 'selected' : null },
					(s.is_zapret ? '⚡ ' : '🛡️ ') + (s.label || s.id) + ' (' + s.id + ', ' + (s.type || '?') + ')');
			})
		);

		var followOpts = this.sectionList().filter(function(x) { return x.is_zapret && x.id !== self.selectedSection; });
		if (!followOpts.length) followOpts = [{ id: '' }];
		var followSelect = E('select', { id: 'fz-follow-from', 'class': 'cbi-input-select', 'style': 'width:240px;', 'change': function() { self.doSaveSection().catch(function() {}); } },
			followOpts.map(function(x) {
				return E('option', { 'value': x.id, 'selected': (sel.follow_from === x.id) ? 'selected' : null }, x.id ? (x.label ? (x.label + ' (' + x.id + ')') : x.id) : '— нет других zapret-секций —');
			})
		);

		var followBox = E('div', { id: 'fz-follow-box', 'style': 'display:' + (sec.is_zapret ? 'flex' : 'none') + '; align-items:center; gap:10px; margin-top:8px; flex-wrap:wrap;' }, [
			E('label', { 'style': 'display:inline-flex; align-items:center; gap:6px; cursor:pointer;' }, [
				E('input', { 'type': 'checkbox', 'id': 'fz-follow-en', 'checked': (sel.follow_enabled === '1') ? 'checked' : null, 'change': function() { self.toggleFollowMode(); self.doSaveSection().catch(function() {}); } }),
				E('span', { 'style': 'font-weight:500;' }, 'Применять настройки из секции:')
			]),
			followSelect
		]);

		var sectionBar = E('div', { 'class': 'cbi-section', 'style': 'padding:12px 16px; margin-bottom:12px;' }, [
			E('div', { 'style': 'display:flex; align-items:center; gap:10px; flex-wrap:wrap;' }, [
				E('span', { 'style': 'font-weight:bold;' }, 'Секция:'),
				secSelect,
				E('span', { 'id': 'fz-sec-role', 'style': 'font-size:12px; color:#9ca3af;' }, sec.is_zapret ? '⚡ zapret-секция (стратегии применяются)' : '🛡️ не zapret (только домены/маршрут)'),
				E('button', { 'class': 'btn cbi-button cbi-button-action', 'style': 'padding:4px 10px; font-size:12px;', 'title': 'Обновить список секций из Forkop', 'click': ui.createHandlerFn(this, 'handleRefreshSections') }, '🔄 Обновить секции')
			]),
			followBox,
			E('div', { 'id': 'fz-follow-note', 'style': 'display:none; margin-top:10px; padding:10px 14px; background:rgba(59,130,246,0.12); border-left:4px solid #3b82f6; color:#93c5fd; font-size:13px;' }, 'Режим «Применять настройки из секции»: стратегия для выбранной выше секции будет взята из секции-источника при сохранении и при каждом изменении её стратегии.')
		]);

		var catDefs = [
			{ id: 'general', label: 'General v1–v11' },
			{ id: 'faketls', label: 'FakeTLS' },
			{ id: 'youtube', label: 'YouTube' },
			{ id: 'discord', label: 'Discord' },
			{ id: 'gv', label: 'Игровые' }
		];
		var catCheckboxes = catDefs.map(function(c) {
			var isChk = savedCats.indexOf(c.id) !== -1;
			return E('label', { 'style': 'display:inline-flex; align-items:center; gap:6px; padding:6px 12px; margin:4px; background:#1e293b; border:1px solid #3b82f6; border-radius:6px; cursor:pointer;' }, [
				E('input', { 'type': 'checkbox', 'id': 'fz-cat-' + c.id, 'class': 'fz-cat-cb', 'value': c.id, 'checked': isChk ? 'checked' : null, 'change': function() { self.saveAutoSettings(); } }),
				E('span', { 'style': 'font-weight:600; color:#e2e8f0;' }, c.label)
			]);
		});

		var ss = (state.section_strategies || {})[this.selectedSection] || {};
		var bestName = ss.best_strategy || state.best_strategy || '';

		var chkSections = this.sectionList().map(function(s) {
			return E('label', { 'style': 'display:inline-flex; align-items:center; gap:8px; padding:8px 12px; margin:4px; background:#1f2937; border:1px solid ' + (s.is_zapret ? '#10b981' : '#4b5563') + '; border-radius:6px; cursor:pointer;' }, [
				E('input', { 'type': 'checkbox', 'class': 'fz-chk-sec-cb', 'value': s.id, 'checked': s.is_zapret ? 'checked' : null }),
				E('span', { 'style': 'font-weight:600; color:#f9fafb;' }, s.label ? (s.label + ' (' + s.id + ')') : s.id),
				E('span', { 'style': 'font-size:11px; color:' + (s.is_zapret ? '#34d399' : '#9ca3af') + ';' }, s.is_zapret ? '⚡ ZAPRET' : '🛡️ VPN/DNS')
			]);
		});
		var filterCb = function(id, label) {
			return E('label', { 'style': 'display:inline-flex; align-items:center; gap:6px; cursor:pointer; color:#e2e8f0;' }, [
				E('input', { 'type': 'checkbox', 'id': id, 'checked': 'checked', 'change': function() { self.applyCheckFilters(); } }),
				E('span', {}, label)
			]);
		};

		var viewNode = E('div', { 'class': 'cbi-map' }, [
			E('div', { 'style': 'display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;' }, [
				E('h2', { 'style': 'margin:0;' }, 'Управление стратегиями Zapret для Forkop'),
				E('span', { 'id': 'fz-status-badge', 'style': 'padding:4px 12px; border-radius:999px; color:#fff; font-size:12px; font-weight:bold; background:' + (this.isRunning ? '#2563eb' : '#4b5563') }, this.isRunning ? 'ВЫПОЛНЯЕТСЯ' : 'ОЖИДАНИЕ')
			]),

			sectionBar,

			E('div', { 'id': 'fz-tab-buttons', 'style': 'display:flex; gap:10px; margin-bottom:14px; flex-wrap:wrap;' }, [
				E('button', { 'id': 'fz-tabbtn-auto', 'class': 'btn', 'style': 'padding:8px 18px; font-weight:bold; color:#fff; background:#2563eb; border:1px solid #3b82f6; border-radius:6px; cursor:pointer;', 'click': function() { self.switchTab('auto'); } }, '🔍 Автоподбор'),
				E('button', { 'id': 'fz-tabbtn-builder', 'class': 'btn', 'style': 'padding:8px 18px; font-weight:bold; color:#fff; background:#1f2937; border:1px solid #374151; border-radius:6px; cursor:pointer;', 'click': function() { self.switchTab('builder'); } }, '🛠️ Ручной конструктор'),
				E('button', { 'id': 'fz-tabbtn-check', 'class': 'btn', 'style': 'padding:8px 18px; font-weight:bold; color:#fff; background:#1f2937; border:1px solid #374151; border-radius:6px; cursor:pointer;', 'click': function() { self.switchTab('check'); } }, '🔎 Проверка доменов'),
				E('button', { 'id': 'fz-tabbtn-settings', 'class': 'btn', 'style': 'padding:8px 18px; font-weight:bold; color:#fff; background:#1f2937; border:1px solid #374151; border-radius:6px; cursor:pointer;', 'click': function() { self.switchTab('settings'); } }, '⚙️ Настройки')
			]),

			// === Вкладка 1: Автоподбор ===
			E('div', { 'id': 'fz-tab-auto', 'style': 'display:block;' }, [
				E('div', { 'class': 'cbi-section', 'style': 'padding:16px;' }, [
					E('h3', { 'style': 'margin-top:0;' }, 'Категории стратегий для автоподбора выбранной секции'),
					E('p', { 'style': 'margin:0 0 8px 0; font-size:12px; color:#9ca3af;' }, 'Порядок: контроль без стратегий → боевая (из секции) → кастомная → быстрый гибрид → категории → финальные комбинации.'),
					E('div', { 'style': 'display:flex; flex-wrap:wrap; align-items:center; margin-bottom:12px;' }, catCheckboxes),
					E('div', { 'style': 'margin-bottom:16px; padding:8px 12px; background:#111827; border:1px solid #374151; border-radius:6px;' }, [
						E('label', { 'style': 'display:inline-flex; align-items:center; gap:8px; cursor:pointer;' }, [
							E('input', { 'type': 'checkbox', 'id': 'fz-all-combos', 'checked': (sel.all_combos === '1') ? 'checked' : null, 'change': function() { self.saveAutoSettings(); } }),
							E('span', { 'style': 'font-weight:bold; color:#fde047;' }, '🔀 Все комбинации (медленно)')
						])
					]),
					E('div', { 'id': 'fz-best-box', 'style': 'margin-bottom:16px; padding:10px 14px; background:rgba(16,185,129,0.15); border-left:4px solid #10b981; color:#34d399; font-weight:bold;' }, bestName ? ('★ Сохранённая стратегия секции: ' + bestName) : 'Стратегия для этой секции ещё не подобрана'),
					E('div', { 'style': 'display:flex; gap:12px;' }, [
						E('button', { 'id': 'fz-btn-start', 'class': 'btn cbi-button cbi-button-apply', 'disabled': this.isRunning ? 'disabled' : null, 'click': ui.createHandlerFn(this, 'handleStart') }, '▶ Запустить подбор'),
						E('button', { 'id': 'fz-btn-stop', 'class': 'btn cbi-button cbi-button-reset', 'click': ui.createHandlerFn(this, 'handleStop') }, '■ Остановить')
					])
				]),
				E('div', { 'class': 'cbi-section', 'style': 'padding:16px;' }, [
					E('div', { 'style': 'display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; margin-bottom:8px;' }, [
						E('h3', { 'style': 'margin:0;' }, 'Живой журнал'),
						E('div', { 'style': 'display:flex; align-items:center; gap:16px;' }, [
							E('label', { 'style': 'display:inline-flex; align-items:center; gap:6px; cursor:pointer; font-size:13px; color:#e2e8f0;' }, [
								E('input', { 'type': 'checkbox', 'id': 'fz-autoscroll', 'checked': 'checked' }), E('span', {}, '🔽 Автопрокрутка')
							]),
							E('span', { 'id': 'fz-progress-label', 'style': 'font-weight:bold; color:#38bdf8;' }, '0%')
						])
					]),
					E('div', { 'style': 'width:100%; height:10px; background:#1f2937; border-radius:6px; overflow:hidden; margin-bottom:12px;' }, [
						E('div', { 'id': 'fz-progress-bar', 'style': 'width:0%; height:100%; background:#38bdf8; transition:width 0.3s ease;' })
					]),
					E('div', { 'id': 'fz-console', 'data-empty': '1', 'style': 'background:#0f172a; color:#94a3b8; padding:14px; border-radius:8px; height:440px; overflow-y:auto; border:1px solid #1e293b;' }, 'Ожидание запуска...')
				])
			]),

			// === Вкладка 2: Ручной конструктор ===
			E('div', { 'id': 'fz-tab-builder', 'style': 'display:none;' }, [
				E('div', { 'class': 'cbi-section', 'style': 'padding:16px;' }, [
					E('div', { 'style': 'display:flex; justify-content:space-between; align-items:center; gap:10px; flex-wrap:wrap;' }, [
						E('h3', { 'style': 'margin:0;' }, '🛠️ Ручной конструктор стратегии'),
						E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'handleRefreshStrategies') }, '🔄 Обновить стратегии')
					]),
					E('p', { 'style': 'margin:0 0 12px 0; font-size:12px; color:#9ca3af;' }, 'Собранная стратегия применяется в выбранную выше секцию.'),
					E('div', { 'style': 'display:grid; grid-template-columns:repeat(auto-fit, minmax(340px, 1fr)); gap:16px; margin-bottom:18px;' }, [
						E('div', {}, [E('label', { 'style': 'display:block; font-weight:bold; margin-bottom:6px;' }, '1. Основное ядро:'), E('select', { 'id': 'fz-bld-core', 'class': 'cbi-input-select', 'style': 'width:100%;', 'change': function() { self.updateBuilderPreview(); } }, makeOpts(CORE_PRESETS, 'General_v11_Forkop_OneTrust'))]),
						E('div', {}, [E('label', { 'style': 'display:block; font-weight:bold; margin-bottom:6px;' }, '2. YouTube:'), E('select', { 'id': 'fz-bld-yt', 'class': 'cbi-input-select', 'style': 'width:100%;', 'change': function() { self.updateBuilderPreview(); } }, makeOpts(YT_PRESETS, 'same'))]),
						E('div', {}, [E('label', { 'style': 'display:block; font-weight:bold; margin-bottom:6px;' }, '3. Discord Media:'), E('select', { 'id': 'fz-bld-disctcp', 'class': 'cbi-input-select', 'style': 'width:100%;', 'change': function() { self.updateBuilderPreview(); } }, makeOpts(DISC_TCP_PRESETS, 'Discord_Dv_MD5'))]),
						E('div', {}, [E('label', { 'style': 'display:block; font-weight:bold; margin-bottom:6px;' }, '4. Fake-файл Discord Voice:'), E('select', { 'id': 'fz-bld-discbin', 'class': 'cbi-input-select', 'style': 'width:100%;', 'change': function() { self.updateBuilderPreview(); } }, makeOpts(DISC_FAKE_BINS, 'quic_initial_steamcommunity_com.bin'))]),
						E('div', {}, [E('label', { 'style': 'display:block; font-weight:bold; margin-bottom:6px;' }, '5. Игровой профиль:'), E('select', { 'id': 'fz-bld-game', 'class': 'cbi-input-select', 'style': 'width:100%;', 'change': function() { self.updateBuilderPreview(); } }, makeOpts(GAME_PRESETS, 'Game_Gv1_Cutoff_d2'))])
					]),
					E('label', { 'style': 'display:block; font-weight:bold; margin-bottom:6px;' }, 'Итоговая строка:'),
					E('textarea', { 'id': 'fz-bld-preview', 'style': 'width:100%; height:130px; background:#020617; color:#fde047; font-family:monospace; font-size:12px; padding:10px; border:1px solid #334155; border-radius:6px; margin-bottom:14px;' }, ''),
					E('div', { 'style': 'display:flex; gap:12px;' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, 'handleApplyCustom') }, '⚡ Применить в выбранную секцию'),
						E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) {
							var pr = document.getElementById('fz-bld-preview');
							if (pr) self.copyStrategyText(pr.value, ev.target);
						}}, '📋 Скопировать')
					])
				])
			]),

			// === Вкладка: Проверка доменов ===
			E('div', { 'id': 'fz-tab-check', 'style': 'display:none;' }, [
				E('div', { 'class': 'cbi-section', 'style': 'padding:16px;' }, [
					E('h3', { 'style': 'margin-top:0;' }, '🔎 Проверка доменов'),
					E('p', { 'style': 'margin:0 0 8px 0; font-size:12px; color:#9ca3af;' }, 'Домены берутся из отмеченных секций (без доменов ZM).'),
					E('div', { 'style': 'display:flex; flex-wrap:wrap;' }, chkSections),
					E('div', { 'style': 'display:flex; gap:12px; margin-top:14px; flex-wrap:wrap;' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, 'handleCheckBlock') }, '1. Проверить блокировку доменов'),
						E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'handleCheckForkop') }, '2. Проверить доступность через forkop'),
						E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.createHandlerFn(this, 'handleStopCheck') }, '■ Остановить проверку')
					]),
					E('div', { 'style': 'display:flex; gap:8px; margin-top:14px; flex-wrap:wrap; align-items:center;' }, [
						E('input', { 'type': 'text', 'id': 'fz-chk-domain', 'class': 'cbi-input-text', 'style': 'width:380px;', 'placeholder': 'example.com — проверить только этот домен' }),
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function() { self.runSingleCheck('block'); } }, 'Блокировка'),
						E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': function() { self.runSingleCheck('forkop'); } }, 'Через forkop')
					])
				]),
				E('div', { 'class': 'cbi-section', 'style': 'padding:16px;' }, [
					E('div', { 'style': 'display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; margin-bottom:8px;' }, [
						E('h3', { 'style': 'margin:0;' }, 'Результаты'),
						E('span', { 'id': 'fz-chk-status', 'style': 'padding:4px 12px; border-radius:999px; color:#fff; font-size:12px; font-weight:bold; background:#4b5563;' }, 'ОЖИДАНИЕ')
					]),
					E('div', { 'style': 'display:flex; flex-wrap:wrap; gap:14px; margin-bottom:10px; font-size:13px;' }, [
						filterCb('fz-chk-f-ok', 'Домен доступен'),
						filterCb('fz-chk-f-dns', 'Домена нет в DNS'),
						filterCb('fz-chk-f-ip', 'Заблокирован по IP'),
						filterCb('fz-chk-f-dpi', 'Заблокирован по DPI')
					]),
					E('div', { 'id': 'fz-chk-console', 'data-empty': '1', 'style': 'background:#0f172a; color:#94a3b8; padding:14px; border-radius:8px; height:420px; overflow-y:auto; border:1px solid #1e293b; font-family:monospace; font-size:12px;' }, 'Ожидание проверки...')
				])
			]),

			// === Вкладка 3: Настройки (для выбранной секции) ===
			E('div', { 'id': 'fz-tab-settings', 'style': 'display:none;' }, [
				E('div', { 'class': 'cbi-section', 'style': 'padding:16px;' }, [
					E('h3', { 'style': 'margin-top:0;' }, '1. Обновления и загрузка'),
					E('div', { 'style': 'margin:8px 0 14px 0;' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'handleUpdateAddon') }, '🔄 Обновить аддон (сохранить настройки)')
					]),
					E('pre', { 'id': 'fz-update-console', 'style': 'display:none; background:#0f172a; color:#94a3b8; padding:12px; border-radius:8px; max-height:260px; overflow:auto; font-family:monospace; font-size:11px; margin:0 0 14px 0; white-space:pre-wrap;' }, ''),
					E('div', { 'style': 'display:flex; flex-direction:column; gap:12px; margin-bottom:20px;' }, [
						E('div', { 'style': 'display:flex; align-items:center; gap:10px;' }, [
							E('span', { 'style': 'font-weight:500; min-width:260px;' }, 'Скачивание через VPN-секцию:'),
							E('select', { 'id': 'fz-vpn-sec', 'class': 'cbi-input-select', 'style': 'width:320px;' }, (function() {
								var opts = [E('option', { 'value': 'none' }, 'Напрямую')];
								self.sectionList().forEach(function(s) { if (!s.is_zapret) opts.push(E('option', { 'value': s.id, 'selected': (sel.vpn_section === s.id) ? 'selected' : null }, 'VPN-секция: ' + (s.label || s.id) + ' (' + s.id + ')')); });
								return opts;
							})())
						]),
						E('label', { 'style': 'display:flex; align-items:center; gap:8px; cursor:pointer;' }, [
							E('input', { 'type': 'checkbox', 'id': 'fz-only-strat', 'checked': (sel.only_strat_update !== '0') ? 'checked' : null }),
							E('span', { 'style': 'font-weight:500;' }, 'Не обновлять .bin, только стратегии')
						]),
						E('label', { 'style': 'display:flex; align-items:center; gap:8px; cursor:pointer;' }, [
							E('input', { 'type': 'checkbox', 'id': 'fz-dis-updates', 'checked': (sel.disable_updates === '1') ? 'checked' : null }),
							E('span', { 'style': 'font-weight:500;' }, 'Отключить обновления из интернета')
						])
					]),

					E('h3', {}, '2. DNS и домены ZM'),
					E('p', { 'style': 'margin:0 0 8px 0; font-size:12px; color:#9ca3af;' }, 'Серверы проверяются по очереди: если домен не найден в первом — ищется во втором и т.д.'),
					E('div', { 'id': 'fz-dns-rows', 'style': 'display:flex; flex-direction:column; gap:8px; margin-bottom:10px;' }, (function() {
						var list = (sel.dns_servers || '').split(';').filter(Boolean);
						if (!list.length) list = [(sel.dns_proto || 'doh') + '|' + (sel.dns_server || '8.8.8.8')];
						return list.map(function(e) { return self.dnsRow(e); });
					})()),
					E('button', { 'class': 'btn cbi-button cbi-button-add', 'click': function() { self.addDnsRow(); } }, '+ Добавить DNS-сервер'),
					E('div', { 'style': 'display:flex; flex-direction:column; gap:12px; margin:14px 0 20px 0;' }, [
						E('label', { 'style': 'display:flex; align-items:center; gap:8px; cursor:pointer;' }, [
							E('input', { 'type': 'checkbox', 'id': 'fz-inc-zm', 'checked': (sel.include_zm_domains === '1') ? 'checked' : null, 'change': function() { self.saveAutoSettings(); } }),
							E('span', { 'style': 'font-weight:bold; color:#34d399;' }, '🌐 Включить домены ZM по умолчанию')
						])
					]),

					E('h3', {}, '3. Автоподстановка и период проверки'),
					E('div', { 'style': 'display:flex; flex-direction:column; gap:12px; margin-bottom:20px;' }, [
						E('label', { 'style': 'display:flex; align-items:center; gap:8px; cursor:pointer;' }, [
							E('input', { 'type': 'checkbox', 'id': 'fz-auto-apply', 'checked': (sel.auto_apply !== '0') ? 'checked' : null, 'change': function() { self.saveAutoSettings(); } }),
							E('span', { 'style': 'font-weight:500;' }, 'Автоприменять лучшую стратегию')
						]),
						E('div', { 'style': 'display:flex; align-items:center; gap:10px;' }, [
							E('span', { 'style': 'font-weight:500; min-width:260px;' }, 'Период проверки этой секции:'),
							E('select', { 'id': 'fz-cron-sched', 'class': 'cbi-input-select', 'style': 'width:260px;', 'change': function() { self.saveAutoSettings(); } }, [
								E('option', { 'value': 'off', 'selected': (sel.cron_schedule === 'off' || !sel.cron_schedule) ? 'selected' : null }, 'Выключено'),
								E('option', { 'value': '4h', 'selected': (sel.cron_schedule === '4h') ? 'selected' : null }, 'Каждые 4 часа'),
								E('option', { 'value': '6h', 'selected': (sel.cron_schedule === '6h') ? 'selected' : null }, 'Каждые 6 часов'),
								E('option', { 'value': '12h', 'selected': (sel.cron_schedule === '12h') ? 'selected' : null }, 'Каждые 12 часов'),
								E('option', { 'value': 'daily3', 'selected': (sel.cron_schedule === 'daily3') ? 'selected' : null }, 'Ежедневно 03:00'),
								E('option', { 'value': 'daily5', 'selected': (sel.cron_schedule === 'daily5') ? 'selected' : null }, 'Ежедневно 05:00'),
								E('option', { 'value': 'custom', 'selected': (sel.cron_schedule === 'custom') ? 'selected' : null }, 'Своё время/дни')
							])
						]),
						E('div', { 'style': 'display:flex; align-items:center; gap:10px;' }, [
							E('span', { 'style': 'font-weight:500; min-width:260px;' }, 'Своё время (ЧЧ:ММ) и дни (0=Вс..6=Сб):'),
							E('input', { 'type': 'text', 'id': 'fz-auto-time', 'class': 'cbi-input-text', 'style': 'width:90px;', 'value': sel.auto_update_time || '03:00', 'change': function() { self.saveAutoSettings(); } }),
							E('input', { 'type': 'text', 'id': 'fz-auto-days', 'class': 'cbi-input-text', 'style': 'width:120px;', 'value': sel.auto_update_days || '*', 'change': function() { self.saveAutoSettings(); } })
						])
					]),

					E('h3', {}, '4. Кастомная стратегия (проверяется сразу после боевой)'),
					E('textarea', {
						'id': 'fz-custom-strat',
						'style': 'width:100%; height:120px; background:#020617; color:#fde047; font-family:monospace; font-size:11px; padding:10px; border:1px solid #334155; border-radius:6px; margin-bottom:14px;',
						'placeholder': 'Вставьте свою стратегию — она будет проверена после боевой и сравнена с остальными.'
					}, sel.custom_strategy || ''),
					E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': ui.createHandlerFn(this, 'handleSaveSection') }, '💾 Сохранить настройки секции')
				])
			])
		]);

		setTimeout(function() { self.updateBuilderPreview(); self.toggleFollowMode(); }, 100);
		this.startPolling();
		this.startCheckPolling();
		if (!this._sectionsWatch) {
			this._sectionsWatch = true;
			document.addEventListener('visibilitychange', function() {
				if (document.visibilityState === 'visible') self.checkSectionsChanged();
			});
			window.addEventListener('focus', function() { self.checkSectionsChanged(); });
		}
		return viewNode;
	},

	handleSave: function() { return this.handleSaveSection(); },
	handleSaveApply: null,
	handleReset: null
});
