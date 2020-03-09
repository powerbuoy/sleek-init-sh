<?php
$path = $argv[1] ?? null;

if ($path) {
	$output = "";

	foreach (glob($path) as $file) {
		$content = file_get_contents($file);
		$content = preg_replace('/^(#+) (.*?)$/m', '##$1 $2', $content);
		$content = preg_replace('/^(#{7,}) (.*?)$/m', '**$2**', $content);
		$output .= $content . "\n---\n\n";
	}

	echo $output;
}
