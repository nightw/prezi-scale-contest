<?php
mysql_connect('localhost','root','root');
mysql_select_db('prezi');
$a = mysql_query('select h,queue, count(*) as c from requests WHERE d=\'2013-03-01\' group by d,h,queue ');
while ($b = mysql_fetch_assoc($a)) {
$out[$b['h']][$b['queue']] = $b['c'];

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
			
				$e = $out[$h]['export'];
				$g = $out[$h]['general'];
				$u = $out[$h]['url'];
				echo "['$h',  $e, $g, $u],";
			
		  } ?>
        ]);

        var options = {
          title: 'Sum requests'
        };
		

        var chart = new google.visualization.LineChart(document.getElementById('chart_requests'))
        chart.draw(data, options);
		
		data = google.visualization.arrayToDataTable([
          ['Hour', 'export', 'general','url'],
          <?php
			$a = mysql_query('select h,queue, sum(runtime) as c from requests WHERE d=\'2013-03-01\' group by d,h,queue ');
			while ($b = mysql_fetch_assoc($a)) {
				$out[$b['h']][$b['queue']] = $b['c'];

			}

		  foreach($out as $h=>$data) {
			
				$e = $out[$h]['export'];
				$g = $out[$h]['general'];
				$u = $out[$h]['url'];
				echo "['$h',  $e, $g, $u],";
			
		  } ?>
        ]);

        options = {
          title: 'Sum requested runtime per hour'
        };
		
		
		
		var chart2 = new google.visualization.LineChart(document.getElementById('chart_runtime'));
		chart2.draw(data,options);
		
		data = google.visualization.arrayToDataTable([
          ['Hour', 'export', 'general','url'],
          <?php
			
		  foreach($out as $h=>$data) {
			
				$e = $out[$h]['export'] / 3600;
				$g = $out[$h]['general'] /3600;
				$u = $out[$h]['url'] / 3600;
				echo "['$h',  $e, $g, $u],";
			
		  } ?>
        ]);

        options = {
          title: 'Theoretical minimum number of machines required'
        };
		var chart3 = new google.visualization.LineChart(document.getElementById('chart_min_machine'));
		chart2.draw(data,options);
		
      }
    </script>
  </head>
  <body>
    <div id="chart_requests" style="width: 1300px; height: 600px;"></div>
	<div id="chart_runtime" style="width: 1300px; height: 600px;"></div>
	<div id="chart_min_machine" style="width: 1300px; height: 600px;"></div>
  </body>
</html>