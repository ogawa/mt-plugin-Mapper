# A plugin for converting '[map:address-description]' string into an
# embeded map provided by mapping services.
#
# $Id$
#
# This software is provided as-is. You may use it for commercial or 
# personal use. If you distribute it, please keep this notice intact.
#
# Copyright (c) 2006 Hirotaka Ogawa

package MT::Plugin::Mapper;
use strict;
use MT;
use MT::Template::Context;
use MT::ConfigMgr;
use base 'MT::Plugin';
use vars qw($VERSION);

sub BEGIN {
    $VERSION = '0.10';
    my $plugin = MT::Plugin::Mapper->new({
	name => 'Mapper',
	version => $VERSION,
	description => 'This plugin enables MTMapper container tag, which converts "[map:address-description]" string into an embeded map provided by mapping services such as Google Maps.',
	doc_link => 'http://as-is.net/blog/archives/1108.html',
	author_name => 'Hirotaka Ogawa',
	author_link => 'http://profile.typekey.com/ogawa/',
	blog_config_template => \&blog_config_template,
	settings => new MT::PluginSettings([
					    ['google_maps_key', { Default => '' }]
					    ])
	});
    MT->add_plugin($plugin);
    MT::Template::Context->add_container_tag(Mapper => sub { $plugin->mapper(@_) });
}

sub mapper {
    my $plugin = shift;
    my ($ctx, $args, $cond) = @_;
    my $blog = $ctx->stash('blog') or return;
    my $config = $plugin->get_config_hash('blog:' . $blog->id) or return;

    %$config = (%$config, %$args);
    $config->{unique} = $ctx->stash('entry')->id
	if defined $ctx->stash('entry');
    my $cfg = MT::ConfigMgr->instance;
    $config->{language} ||= $cfg->DefaultLanguage;
    $config->{charset} ||= $cfg->PublishCharset;

    my $mapper_class = __PACKAGE__ . '::' . ($args->{method} || 'Google');
    my $mapper = $mapper_class->new($config);

    defined(my $html = $ctx->stash('builder')->build($ctx, $ctx->stash('tokens'), $cond)) or return;
    $html =~ s!(?:<(?:div|p)\s+[^<>]*class="adr"[^<>]*>\s*([^<>]+)\s*</(?:div|p)>)|(?:<(?:div|p)[^<>]*>\s*\[map:([^]]+)\]\s*</(?:div|p)>)!$mapper->generate($1||$2)!ge;
    $html;
}

sub blog_config_template {
    my $tmpl = <<'EOT';
<p>This plugin enables MTMapper container tag, which converts "[map:address-description]" string into an embeded map provided by mapping services such as Google Maps.</p>

<p>For more details, see <a href="http://as-is.net/blog/archives/001108.html">"MTMapper Plugin - Ogawa::Memoranda"</a>.</p>

<div class="setting">
<div class="label"><label for="google_maps_key">Google Maps API Key:</label></div>
<div class="field">
<input name="google_maps_key" id="google_maps_key" size="80" value="<TMPL_VAR NAME=GOOGLE_MAPS_KEY ESCAPE=HTML>" />
</div>
</div>
EOT
}

package MT::Plugin::Mapper::Google;

use strict;
use MT::Util qw(encode_url);
use LWP::Simple;
use HTML::Template;

sub new {
    my $class = shift;
    my($config) = @_;
    $config->{count} = 0;
    $config->{unique} ||= int(rand(65536));
    bless $config, $class;
}

sub DESTROY { }

sub generate {
    my $this = shift;
    my($s) = @_;
    my($adr, $opt) = split(/:/, $s);
    $adr =~ s/^\s+//;
    $adr =~ s/\s+$//;
    my ($lat, $lon);
    if ($adr =~ m!^x([-.\d]+)y([-.\d]+)$!) {		# map:x<lon>y<lat>
	($lat, $lon) = ($2, $1);
    } elsif ($adr =~ m!^([-.\d]+),\s*([-.\d]+)$!) {	# map:<lat>,<lon>
	($lat, $lon) = ($1, $2);
    } else {
	($lat, $lon) = eval { $this->resolve_address($adr) };
	return "<div class=\"adr\">$adr (Sorry, this address cannot be resolved.)</div>" if $@;
    }
    my $res = '';
    $res .= $this->preamble unless $this->{count};
    $res .= $this->body($lat, $lon, $adr);
    $this->{count}++;
    $res;
}

sub resolve_address {
    my $this = shift;
    my($adr) = @_;
    my $geo_url = $this->{language} eq 'ja' ?
	'http://maps.google.co.jp/maps?q=' : 'http://maps.google.com/maps?q=';
    $geo_url .= encode_url($adr) . '&output=kml';
    $geo_url .= '&ie=' . $this->{charset} . '&oe=' . $this->{charset};
    my $res = get($geo_url);
    if ($res && $res =~ /coordinates>([-.\d]+),([-.\d]+),/is) {
	return ($2, $1);
    } else {
	die "Cannot obtain the coordinates for this address.";
    }
}

my $preamble_tmpl = <<'EOT';
<script type="text/javascript" src="http://maps.google.com/maps?<TMPL_IF NAME="language">hl=<TMPL_VAR NAME="language">&amp;</TMPL_IF>file=api&amp;v=1&amp;key=<TMPL_VAR NAME="google_maps_key">" charset="utf-8"></script>
<script type="text/javascript">
//<![CDATA[
function attachOnLoad(func) {
    var old = window.onload;
    window.onload = (typeof old != 'function') ?
	func : function(e) { old(e); return func(e); };
}
function generateGMap(mapid, address, latitude, longitude, maptype, zoom) {
    if (GBrowserIsCompatible()) {
	var icon = new GIcon();
	icon.image = "http://www.google.com/mapfiles/marker.png";
	icon.shadow = "http://www.google.com/mapfiles/shadow50.png";
	icon.iconSize = new GSize(20, 34);
	icon.shadowSize = new GSize(37, 34);
	icon.iconAnchor = new GPoint(6, 20);
	icon.infoWindowAnchor = new GPoint(5, 1);

	var map = new GMap(document.getElementById(mapid));
	map.setMapType((typeof maptype == 'string') ? eval(maptype) : maptype);
	map.addControl(new GSmallMapControl());
	map.addControl(new GMapTypeControl());
	var point = new GPoint(longitude, latitude);
	map.centerAndZoom(point, zoom);
	var marker = new GMarker(point, icon);
	map.addOverlay(marker);
	var html = '<div style="width:12em;font-size:small">'+address+'</div>';
	GEvent.addListener(marker, 'click', function() {
	    marker.openInfoWindowHtml(html);
	});
    } else {
	document.getElementById(mapid).innerHTML = '<p>The Google Map that should be displayed on this page is not compatible with your browser. Sorry.</p>';
    }
}
//]]>
</script>
EOT

sub preamble {
    my $this = shift;
    my $tmpl = HTML::Template->new(scalarref => \$preamble_tmpl);
    $tmpl->param(
		 google_maps_key => $this->{google_maps_key},
		 language => $this->{language} || ''
		 );
    $tmpl->output;
}

my $body_tmpl = <<'EOT';
<div id="<TMPL_VAR NAME="mapid">" style="width:<TMPL_VAR NAME="width">;height:<TMPL_VAR NAME="height">;" class="adr"><TMPL_VAR NAME="address"></div>
<script type="text/javascript">
//<![CDATA[
attachOnLoad(function() {
    generateGMap('<TMPL_VAR NAME="mapid">','<TMPL_VAR NAME="address">',<TMPL_VAR NAME="latitude">,<TMPL_VAR NAME="longitude">,'<TMPL_VAR NAME="maptype">',<TMPL_VAR NAME="zoom">);
});
//]]>
</script>
EOT

sub body {
    my $this = shift;
    my($lat, $lon, $adr) = @_;
    my $tmpl = HTML::Template->new(scalarref => \$body_tmpl);
    $tmpl->param(
		 mapid => "MTPluginMapperGoogle-" . $this->{unique} . '-' . $this->{count},
		 width => $this->{width} || '400px',
		 height => $this->{height} || '300px',
		 latitude => $lat,
		 longitude => $lon,
		 address => $adr,
		 maptype => $this->{maptype} || 'G_MAP_TYPE',
		 zoom => (defined $this->{zoom}) ? $this->{zoom} : 4
		 );
    $tmpl->output;
}

sub postamble { '' }

package MT::Plugin::Mapper::Alps;

use strict;
use MT::Util qw(encode_url);
use MT::I18N;

sub new {
    my $class = shift;
    my($config) = @_;
    bless $config, $class;
}

sub DESTROY { }

sub generate {
    my $this = shift;
    my($s) = @_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    my($str, $opt) = split(/:/, $s);

    my $pos = '';
    if ($str =~ m!^x([-.\d]+)y([-.\d]+)$!) {		# map:x<lon>y<lat>
	$pos = "$2,$1";
    } elsif ($str =~ m!^([-.\d]+),\s*([-.\d]+)$!) {	# map:<lat>,<lon>
	$pos = $str;
    }
    if ($pos) {
	return qq[<p><a target="_blank" href="http://clip.alpslab.jp/bin/rd?pos=$pos"><img class="alpslab-clip" src="http://clip.alpslab.jp/bin/map?pos=$pos&amp;opt=$opt" alt="$str" title="$str" /></a></p>];
    }

    my $adr = MT::I18N::encode_text($str, '', 'euc-jp') || '';
    $adr = MT::Util::encode_url($adr);
    qq[<p><a target="_blank" href="http://clip.alpslab.jp/bin/rd?adr=$adr"><img class="alpslab-clip" src="http://clip.alpslab.jp/bin/map?adr=$adr&amp;opt=$opt" alt="$str" title="$str" /></a></p>];
}
