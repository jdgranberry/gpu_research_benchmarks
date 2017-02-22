#!/bin/bash
# Dependencies
# CUDA

# TODO enviornment specific variables; needs to be set at install time 
PARBOIL_HOME=$HOME/gpu_research_benchmarks/Parboil
input_dir=${PARBOIL_HOME}/datasets
ref_output_dir=${input_dir}

# Required for --verify option, provides libraries for tools/compare-output
export PYTHONPATH=$PYTHONPATH:$PARBOIL_HOME/common/python


MAKEFILE_DIR=${PARBOIL_HOME}/benchmarks
MAKEFILE="Makefile.conf"

if [ $# -lt 1 ]; then
    echo "usage: "
    echo "  ./parboil_gen_variant.sh <options> prog_num"
    echo "builds a parboil executable with specified regs, blocksizes etc."
    echo ""
    echo "Options: "
    echo "      -v, --verify; check output agains reference"
    echo "      -t, --time; report execution time"
    echo "      -l, --launch, get launch configuration"
    echo "      -s, --showregs, show register allocation"
    echo "      -c, --codetype [cuda_base, cuda]"
    echo "      -r, --regs REGS; REGS legal values, {16..512}" 
    echo "      -d, --dataset [small, medium, large]"
    echo "      -b, --blocksize BLOCKSIZE; BLOCKSIZE legal values {32..1024}" 
    echo "      -a, --ra {LEVEL}; LEVEL legal values {0, 1, 2, 3}; EXPERIMENTAL"
    exit 0
fi

while [ $# -gt 0 ]; do
    key="$1"
    case $key in
        -r|--regs)
            maxreg="$2"
            shift 
            ;;
        -a|--ra)
            ra_level="$2"
            shift 
            ;;
        -v|--verify)
            verify=true
            ;;
        -t|--time)
            perf=true
            ;;
        -d|--dataset)
            dataset="$2"
            shift 
            ;;
        -b|--blocksize)
            blocksize="$2"
            shift 
            ;;
        -m|--max_thrds)
            max_thrds="$2"
            shift 
            ;;
        -n|--min_thrds)
            min_blks="$2"
            shift 
            ;;
        -c|--codetype)
            ver="$2"
            shift 
            ;;
    -l|--launch)
        launch=true
        ;;
    -s|--showregs)
        showregs=true
        ;;
    *)
            # unknown option
            if [ "$prog" = "" ]; then
                prog=$1
            else
                echo "Unknown option:" $key
                exit 0
    fi
    ;;
    esac 
    shift 
done

[ "$prog" ] || { echo "no program specified. exiting ..."; exit 0; }



[ -x ${PARBOIL_HOME} ] || { "unable to cd to Parboil home directory; exiting ..." ; exit 1; }  


if [ "${maxreg}" = "" ]; then 
    maxreg=default
fi
if [ "${blocksize}" = "" ]; then 
    blocksize=default
fi
if [ "${dataset}" = "" ]; then 
    dataset=small
fi
if [ "${ver}" = "" ]; then 
    ver="cuda_base"
fi

if [ ! "${max_thrds}" ]; then 
    if [ ! "${min_blks}" ]; then 
        max_thrds=default
        min_blks=default
    else 
        max_thrds=1024
    fi
else 
    if [ ! "${min_blks}" ]; then 
        min_blks=1
    fi
fi 

if [ $DEBUG ]; then 
    echo $prog
    echo $ver
    echo $maxreg
    echo ${max_thrds}
    echo ${min_blks}
    echo $blocksize
         exit 
fi

cd ${PARBOIL_HOME}
source parboil_vardefs.sh ${input_dir}

function build {
    i=$1
    prog=${progs[$i]}
    ver=$2

    srcdir="${PARBOIL_HOME}/benchmarks/$prog/src/$ver"

    pushd ${MAKEFILE_DIR}  > /dev/null
    cp ${MAKEFILE} ${MAKEFILE}.orig

    sed -i "s/RALEVEL=/RALEVEL=${ra_level}/" ${MAKEFILE}
    if [ ${maxreg} != "default" ]; then
        sed -i "s/REGCAP=/REGCAP=--maxrregcount=${maxreg}/" ${MAKEFILE}
    fi
    if [ ${blocksize} != "default" ]; then
        sed -i "s/BLOCKPARAM=/BLOCKPARAM=-DML/" ${MAKEFILE}
    fi  

        
    if [ ${max_thrds} != "default" ] || [ ${min_blks} != "default" ]; then 
        sed -i "s/LAUNCH=/LAUNCH=-DLAUNCH/" ${MAKEFILE}
        sed -i "s/ML_MAX_THRDS_PER_BLK=/ML_MAX_THRDS_PER_BLK=-DML_MAX_THRDS_PER_BLK=${max_thrds}/" ${MAKEFILE}
        sed -i "s/ML_MIN_BLKS_PER_MP=/ML_MIN_BLKS_PER_MP=-DML_MIN_BLKS_PER_MP=${min_blks}/" ${MAKEFILE}
    fi

    if [ -d  $srcdir ]; then 
        pushd $srcdir > /dev/null
        make clean &> /dev/null

        if [ ${blocksize} != "default" ]; then
            case ${prog} in 
                "lbm") 
                     srcfile=${prog}.cu
                     ;;
                 "mri-gridding")
                     srcfile=CUDA_interface.cu
                     ;;
                 "mri-q")
                     srcfile=computeQ.cu
                     ;;
                 "sgemm"|"tpacf")
                     srcfile=${prog}_kernel.cu
                     ;;
                 "spmv")
                     srcfile=gpu_info.cc
                     ;;
                 "cutcp")
                     srcfile=main.c
                     ;;
                 *)
                     srcfile=main.cu
                     ;;
            esac
                cp ${srcfile} ${srcfile}.orig
                sed -i "s/__BLOCKSIZE0/${blocksize}/" ${srcfile}
        fi  


        # TODO Make output is redirected here, you will not see why makOutput is directed to STDERR here, you will not see why 
        # make is failing. Comment out the following line and uncomment the next to investigate   
      
        regs=`make 2>&1 | grep "registers" | awk '{ print $5 }'`
        #regs=`make -v | grep "registers" | awk '{ print $5 }'`

        if [ $ver = "cuda_base" ]; then 
            if [ $prog = "histo" ]; then
                regs=`echo $regs | awk '{print $3}'`
            fi
            if [ $prog = "mri-gridding" ]; then
                regs=`echo $regs | awk '{print $2}'`
            fi
            if [ $prog = "sad" ]; then
                regs=`echo $regs | awk '{print $1}'`
            fi
            if [ $prog = "track" ]; then
                regs=`echo $regs | awk '{print $1}'`
            fi
                                        
        fi
      
        if [ $ver = "cuda" ]; then 
            if [ $prog = "mri-q" ] || [ $prog = "mri-gridding" ]; then
                regs=`echo $regs | awk '{print $2}'`
            else
                regs=`echo $regs | awk '{print $1}'`
            fi
        fi

        # TODO deprecated (bundled with launch configuration)
        if [ "${showregs}" ]; then 
            echo $regs
        fi

        # Check is executable was generated, otherwise notify of failed build. 
        # TODO should be more expressive if possible 
        if [ ! -x ${prog} ]; then 
            echo "FAIL: could not generate variant executable; make failed for $prog"
            
            if [ ${blocksize} != "default" ]; then
                cp ${srcfile}.orig ${srcfile}
            fi
            popd > /dev/null
        
        # back in makefile dir
            cp ${MAKEFILE}.orig ${MAKEFILE}
            popd > /dev/null
            exit 1
        fi

        if [ "$dataset" = "small" ]; then 
            args=${args_small[$i]} 
        fi
        if [ "$dataset" = "medium" ];then
            args=${args_medium[$i]}
        fi
        if [ "$dataset" = "large" ]; then 
            args=${args_large[$i]}
        fi

        if [ "${verify}" ]; then 
            verification_script="../../tools/compare-output"
                                
            if [ ! -x ${verification_script} ]; then 
            echo "FAIL: could not find check script, not validating results"
            else
                ./${prog} -i $args  > $prog.out
                res=`${verification_script} ${ref_output_dir}/${prog}/ref_${dataset}.dat result.dat 2> /dev/null`
                res=`echo $res | grep "Pass"`
                if [ ! "${res}" ]; then 
                    res="FAIL"
                fi
            fi
        fi
                        
        if [ "${perf}" ]; then 
            # TODO this script needs to be linked from... somewhere.
            $PARBOIL_HOME/get_primary_gpu.sh -m time -- ./${prog} -i $args 
        fi

        if [ "${res}" = "FAIL" ]; then 
            echo $res ": executable not valid" 
        fi
                            
        if [ "${launch}" ]; then 
            if [ $ver = "cuda" ]; then 
                kernel=${kernels[$i]}
            else 
                kernel=${kernels_base[$i]}
            fi
            
            path_to_nvprof=$(which nvprof)
            if [ -x "$path_to_nvprof" ] ; then
                (nvprof --events threads_launched,sm_cta_launched ./${prog} -i $args  > $prog.out) 2> tmp
                geom=`cat tmp | grep "${kernel}" -A 2 | grep "launched" | awk '{print $NF}'`
                thrds_per_block=`echo $geom | awk '{ printf "%5.0f", $1/$2 }'`
                blocks_per_grid=`echo $geom | awk '{ print $2 }'`
                echo  "$prog,$ver,$regs,${blocks_per_grid},${thrds_per_block},"
            else
                # TODO should recover and terminate at this point. Should probably just detect at the beginning and terminate from there.
              
                echo "ERROR: nvprof not found."
            fi              
        fi

        # clean up and restore
        if [ ${blocksize} != "default" ]; then
            cp ${srcfile} ${srcfile}.gen
            cp ${srcfile}.orig ${srcfile}
        fi
        rm -rf tmp $prog.out
        popd > /dev/null
    else
        echo "FAIL: $ver not found for prog $prog" 
    fi

    # back in makefile dir
    cp ${MAKEFILE}.orig ${MAKEFILE}
    popd > /dev/null
}

build $prog $ver
