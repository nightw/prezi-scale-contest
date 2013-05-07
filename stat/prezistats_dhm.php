<?php
mysql_connect('localhost','root','root');
mysql_select_db('prezi');
$a = mysql_query('select d,h,m,queue, count(*) as c from requests  group by d,h,m,queue ; ');
while ($b = mysql_fetch_assoc($a)) {
$out[$b['d'].'-'.$b['h'].':'.$b['m']][$b['queue']] = $b['c'];

}
?>
<html>
  <head>
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart"]});
      google.setOnLoadCallback(drawRequestChart);
      function drawRequestChart() {
        var data = google.visualization.arrayToDataTable([
          ['Hour', 'export', 'general','url'],
          <?php
		  foreach($out as $h=>$data) {
			
			//Memory limit ftw - we throw away, if the given data is not fully accessible.
			if (isset($out[$h]['export']) && isset($out[$h]['general']) && isset($out[$h]['url'])) {
				$e = $out[$h]['export'];
				$g = $out[$h]['general'];
				$u = $out[$h]['url'];
				echo "['$h',  $e, $g, $u],";
			}
			
		  } ?>
        ]);

        var options = {
          title: 'Sum requests'
        };
		

        var chart = new google.visualization.LineChart(document.getElementById('chart_requests'))
        chart.draw(data, options);
		
      }
    </script>
  </head>
  <body>
    <div id="chart_requests" style="width: 1300px; height: 600px;"></div>
	<div id="chart_runtime" style="width: 1300px; height: 600px;"></div>
	<div id="chart_min_machine" style="width: 1300px; height: 600px;"></div>
  </body>
</html>