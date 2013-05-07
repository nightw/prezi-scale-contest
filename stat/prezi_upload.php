<?php
mysql_connect('localhost','root','root');
mysql_select_db('prezi');
$a = fopen('week_1.log','r');
$linecount = 0;

$handle = fopen('week_1.log', "r");
echo 'Initializing...'."\n";
while(!feof($handle)){
  $line = fgets($handle);
  $linecount++;
}
fclose($handle);
echo "Input file has $linecount lines.\n";
$percentage = 0;
$line = 0;
while ($b = fgets($a)) {
	$items = explode(' ',$b);
	
	$time = explode(':',$items[1]);
	
	mysql_query('INSERT INTO requests(d,h,m,s,queue,runtime) VALUES("'.$items[0].'",'.$time[0].','.$time[1].','.$time[2].',"'.$items[3].'",'.$items[4].');');
	$line++;
	if ($line % 1000 == 0) {
		echo $line."/"."$linecount line (".($line/$linecount*100)."%) done. \n";
	}
	
}


?>