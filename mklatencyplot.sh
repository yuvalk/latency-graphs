#!/bin/bash

display_usage() {
    echo "Usage: "
    echo "$0 <cyclictest output filename>"
    exit 1
}

if [ ! $# -eq 1 ]
then
    display_usage
fi

cyclictest_output=$1

if [ -z ${workdir+x} ]
then
    workdir=$(mktemp -d -t oslat-XXXXXX)
elif [ ! -d ${workdir} ]
then
    echo "${workdir} does not exist"
    exit 2
fi

cp ${cyclictest_output} ${workdir}/data.dat
pushd $workdir > /dev/null
cyclictest_output=data.dat

# 1. Get cyclictest time parameter
cyclictest=$(cat ${cyclictest_output} | grep cyclictest | head -1)

unset next_one_is_real
IFS=" " read -ra CARGS <<< "$cyclictest"
for i in "${CARGS[@]}"; do
	if [ ! -z $next_one_is_real ]
	then
		time=$i
		break
	fi
	if [ $i = "-D" ]
	then
		next_one_is_real=true
	fi
done

# 2. Get maximum latency
max=`grep "Max Latencies" ${cyclictest_output} | tr " " "\n" | sort -n | tail -1 | sed s/^0*//`
if [ -z $skip_below ]
then
	skip_below=0
fi

# 3. Grep data lines, remove empty lines and create a common field separator
grep -v -e "^#" -e "^$" ${cyclictest_output} | tr " " "\t" >histogram 

# 4. Set the number of cores, for example
cores=`tail -1 histogram | awk '{print NF - 1}'`

# 5. Create two-column data sets with latency classes and frequency values for each core, for example
for i in `seq 1 $cores`
do
  column=`expr $i + 1`
  cut -f1,$column histogram >histogram$i
done

# 6. Create plot command header
echo -n -e "set title \"Latency plot $time above $skip_below\"\n\
set terminal png\n\
set xlabel \"Latency (us), max $max us\"\n\
set logscale y\n\
set xrange [0:$max]\n\
set yrange [0.8:*]\n\
set ylabel \"Number of latency samples\"\n\
set output \"plot.png\"
plot " >plotcmd

# 7. Append plot command data references
maxlats=$(grep "Max Latencies" data.dat | sed 's/# Max Latencies: //')
IFS=" " read -ra maxlatarr <<< "$maxlats"

unset is_not_first
for i in `seq 1 $cores`
do
  cpuno=`expr $i - 1`
  if [ "${maxlatarr[$i-1]}" -gt "$skip_below" ]
  then
	if [ ! -z $is_not_first ]
	then
		echo -n ", " >>plotcmd
	else
		is_not_first=true
	fi

	if test $cpuno -lt 10
	then
		title=" CPU$cpuno"
	else
		title="CPU$cpuno"
	fi
	echo -n "\"histogram$i\" using 1:2 title \"$title\" with histeps" >>plotcmd
  else
	  echo "Skipping CPU $cpuno, it's max latency is only ${maxlatarr[$i-1]}"
  fi
done

# 8. Execute plot command
gnuplot -persist <plotcmd
echo "plot is ready at ${workdir}/plot.png"

popd > /dev/null
