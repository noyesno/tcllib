#-----------------------------------------------------------------------
# TITLE:
#	snit.tcl
#
# AUTHOR:
#	Will Duquette
#
# DESCRIPTION:
#       Snit's Not Incr Tcl: yet another simple object system in Pure Tcl, 
#	just because I wanted to.
#
#-----------------------------------------------------------------------

package provide snit 0.82

#-----------------------------------------------------------------------
# Namespace

namespace eval ::snit:: {
    namespace export type widget widgetadaptor
}

#-----------------------------------------------------------------------
# Standard method and typemethod definition templates

namespace eval ::snit:: {
    variable reservedArgs {type selfns win self}

    # If true, get a pretty, fixed-up stack trace.  Otherwise, get raw
    # stack trace.
    variable prettyStackTrace 1

    # The elements of defs are standard methods and typemethods; it's
    # most convenient to define these as though they'd been typed in by
    # the class author.  The following tokens will be substituted:
    #
    # %TYPE%    The type name
    #
    variable defs

    # Methods common to both types and widgettypes.
    set defs(common) {
        # Options array
        variable options

        # Instance Introspection: info <command> <args>
        method info {command args} {
            global errorInfo

            switch -exact $command {
                type    -
                vars    -
                options -
                typevars {
                    set errflag [catch {
                        uplevel ::snit::InstanceInfo_$command \
                            $type $selfns $win $self $args
                    } result]

                    if {$errflag} {
                        return -code error -errorinfo $errorInfo $result
                    } else {
                        return $result
                    }
                }
                default {
                    error "'$self info $command' is not defined."
                }
            }
        }

        # Type Introspection: info <command> <args>
        typemethod info {command args} {
            global errorInfo

            switch -exact $command {
                typevars - 
                instances {
                    set errflag [catch {
                        uplevel ::snit::TypeInfo_$command \
                            $type $args
                    } result]

                    if {$errflag} {
                        return -code error -errorinfo $errorInfo $result
                    } else {
                        return $result
                    }
                }
                default {
                    error "'$type info $command' is not defined."
                }
            }
        }

        method cget {option} {
            typevariable Snit_optiondefaults
            typevariable Snit_delegatedoptions
                
            if {[info exists Snit_optiondefaults($option)]} {
                # Normal option; return it.
                return [Snit_cget$option $type $selfns $win $self]
            } elseif {[info exists Snit_delegatedoptions($option)]} {
                # Delegated option: get target.
                set comp [lindex $Snit_delegatedoptions($option) 0]
                set target [lindex $Snit_delegatedoptions($option) 1]
            } elseif {[info exists Snit_delegatedoptions(*)]} {
                # Unknown option, but unknowns are delegated; get target.
                set comp [lindex $Snit_delegatedoptions(*) 0]
                set target $option
            } else {
                # Use quotes because Tk does.
                error "unknown option \"$option\""
            }
            
            # Get the component's object.
            set obj [Snit_component $selfns $comp]

            # TBD: I'll probably want to fix up certain error
            # messages, but I'm not sure how yet.
            return [$obj cget $target]
        }

        method configurelist {optionlist} {
            typevariable Snit_optiondefaults
            typevariable Snit_delegatedoptions

            foreach {option value} $optionlist {
                if {[info exist Snit_optiondefaults($option)]} {
                    Snit_configure$option $type $selfns $win $self $value
                    continue
                } elseif {[info exists Snit_delegatedoptions($option)]} {
                    # Delegated option: get target.
                    set comp [lindex $Snit_delegatedoptions($option) 0]
                    set target [lindex $Snit_delegatedoptions($option) 1]
                } elseif {[info exists Snit_delegatedoptions(*)]} {
                    # Unknown option, but unknowns are delegated.
                    set comp [lindex $Snit_delegatedoptions(*) 0]
                    set target $option
                } else {
                    # Use quotes because Tk does.
                    error "unknown option \"$option\""
                }

                # Get the component's object
                set obj [Snit_component $selfns $comp]
                    
                # TBD: I'll probably want to fix up certain error
                # messages, but I'm not sure how yet.
                $obj configure $target $value
            }
            
            return
        }

        method configure {args} {
            typevariable Snit_delegatedoptions
            typevariable Snit_optiondefaults

            # If two or more arguments, set values as usual.
            if {[llength $args] >= 2} {
                $self configurelist $args
                return
            }

            # If zero arguments, acquire data for each known option
            # and return the list
            if {[llength $args] == 0} {
                set result {}
                foreach opt [$self info options] {
                    lappend result [$self configure $opt]
                }

                return $result
            }

            # They want it for just one.
            upvar ${selfns}::Snit_components Snit_components
            set opt [lindex $args 0]
            if {[info exists options($opt)]} {
                return [list $opt "" "" $Snit_optiondefaults($opt) \
                            [$self cget $opt]]
            } elseif {[info exists Snit_delegatedoptions($opt)]} {
                set logicalName [lindex $Snit_delegatedoptions($opt) 0]
                set realOpt [lindex $Snit_delegatedoptions($opt) 1]
            } elseif {[info exists Snit_delegatedoptions(*)]} {
                set logicalName [lindex $Snit_delegatedoptions(*) 0]
                set realOpt $opt
            } else {
                error "unknown option \"$opt\""
            }

            set comp $Snit_components($logicalName)

            if {[catch {set value [$comp cget $realOpt]} result]} {
                error "unknown option \"$opt\""
            }

            if {![catch {$comp configure $realOpt} result]} {
                # Replace the delegated option name with the local name.
                return [snit::Expand $result $realOpt $opt]
            }

            # configure didn't work; return simple form.
            return [list $opt "" "" "" $value]
        }

        # $type destroy
        #
        # Destroys a type completely.
        typemethod destroy {} {
            typevariable Snit_isWidget

            # FIRST, destroy all instances
            foreach selfns [namespace children $type] {
                if {![namespace exists $selfns]} {
                    continue
                }
                upvar ${selfns}::Snit_instance obj
                
                if {$Snit_isWidget} {
                    destroy $obj
                } else {
                    if {"" != [info commands $obj]} {
                        $obj destroy
                    }
                }
            }

            # NEXT, destroy the type's data.
            namespace delete $type

            # NEXT, get rid of the type command.
            rename $type ""
        }
    }

    # Methods specific to plain types.
    set defs(type) {
        # Calls Snit_cleanup, which (among other things) calls the
        # user's destructor.
        method destroy {} {
            Snit_cleanup $selfns $win
        }

        # Creates a new instance of the type given its name and the args.
        typemethod create {name args} {
            typevariable Snit_info
            typevariable Snit_optiondefaults

            # FIRST, qualify the name.
            if {![string match "::*" $name]} {
                # Get caller's namespace; 
                # append :: if not global namespace.
                set ns [uplevel 1 namespace current]
                if {"::" != $ns} {
                    append ns "::"
                }
        
                set name "$ns$name"
            }

            # NEXT, if %AUTO% appears in the name, generate a unique 
            # command name.
            if {[string match "*%AUTO%*" $name]} {
                set name [snit::UniqueName Snit_info(counter) $type $name]
            }

            # NEXT, create the instance's namespace.
            set selfns \
                [snit::UniqueInstanceNamespace Snit_info(counter) %TYPE%]
            namespace eval $selfns {}

            # NEXT, install the dispatcher
            Snit_install $selfns $name

            # Initialize the options to their defaults. 

            upvar ${selfns}::options options
            foreach opt $Snit_info(options) {
                set options($opt) $Snit_optiondefaults($opt)
            }

            # Initialize the instance vars to their defaults.
            # selfns must be defined, as it is used implicitly.
            Snit_instanceVars $selfns

            # Execute the type's constructor.
            set errcode [catch {
                eval Snit_constructor %TYPE% $selfns \
                    [list $name] [list $name] $args
            } result]

            if {$errcode} {
                Snit_cleanup $selfns $name
                error $result
            }

            # NEXT, return the object's name.
            return $name
        }
    }

    # Methods specific to widgets.
    set defs(widget) {
        # Creates a new instance of the widget, given the name and args.
        typemethod create {name args} {
            typevariable Snit_info
            typevariable Snit_optiondefaults
            typevariable Snit_isWidgetAdaptor

            # FIRST, if %AUTO% appears in the name, generate a unique 
            # command name.
            if {[string match "*%AUTO%*" $name]} {
                set name [snit::UniqueName Snit_info(counter) $type $name]
            }
            
            # NEXT, create the instance's namespace.
            set selfns \
                [snit::UniqueInstanceNamespace Snit_info(counter) %TYPE%]
            namespace eval $selfns { }
            
            # Initialize the widget's own options to their defaults.
            upvar ${selfns}::options options
            foreach opt $Snit_info(options) {
                set options($opt) $Snit_optiondefaults($opt)
            }

            # Initialize the instance vars to their defaults.
            Snit_instanceVars $selfns

            # NEXT, if this is a normal widget (not a widget adaptor) then 
            # create a frame as its hull.
            if {!$Snit_isWidgetAdaptor} {
                set self $name
		package require Tk
                installhull [frame $name]
            }

            # Execute the type's constructor, and verify that it
            # has a hull.
            set errcode [catch {
                eval Snit_constructor %TYPE% $selfns [list $name] \
                    [list $name] $args

                Snit_component $selfns hull

                # Prepare to call the object's destructor when the
                # <Destroy> event is received.  Use a Snit-specific bindtag
                # so that the widget name's tag is unencumbered.

                bind Snit%TYPE%$name <Destroy> [::snit::Expand {
                    %TYPE%::Snit_cleanup %NS% %W
                } %NS% $selfns]
                
                # Insert the bindtag into the list of bindtags right
                # after the widget name.
                set taglist [bindtags $name]
                set ndx [lsearch $taglist $name]
                incr ndx
                bindtags $name [linsert $taglist $ndx Snit%TYPE%$name]
            } result]

            if {$errcode} {
                global errorInfo

                set errInfo $errorInfo
                Snit_cleanup $selfns $name
                error "Error in constructor: $result" $errInfo
            }
            
            # NEXT, return the object's name.
            return $name
        }
    }
}

#-----------------------------------------------------------------------
# Snit Type Implementation template

namespace eval ::snit:: {
    # Template type definition: All internal and user-visible Snit
    # implementation code.
    #
    # The following placeholders will automatically be replaced with
    # the client's code, in two passes:
    #
    # First pass:
    # %COMPILEDDEFS%  The compiled type definition.
    #
    # Second pass:
    # %TYPE%          The fully qualified type name.
    # %IVARDECS%      Instance variable declarations
    # %TVARDECS%      Type variable declarations
    # %INSTANCEVARS%  The compiled instance variable initialization code.
    
    variable typeTemplate {
        #----------------------------------------------------------------
        # Snit Internals
        #
        # These commands are used internally by Snit, and are not to be
        # used directly by any client code.  Nevertheless they are
        # defined here so that they live in the correct namespace.

        # Snit_cleanup selfns win
        #
        # This is the function that really cleans up; it's automatically 
        # called when any instance is destroyed, e.g., by "$object destroy"
        # for types, and by the <Destroy> event for widgets.
        proc Snit_cleanup {selfns win} {
            typevariable Snit_isWidget

            # If the variable Snit_instance doesn't exist then there's no
            # instance command for this object -- it's most likely a 
            # widgetadaptor. Consequently, there are some things that
            # we don't need to do.
            if {[info exists ${selfns}::Snit_instance]} {
                upvar ${selfns}::Snit_instance instance

                # First, remove the trace on the instance name, so that we
                # don't call Snit_cleanup recursively.
                Snit_removetrace $selfns $win $instance

                # Next, call the user's destructor
                Snit_destructor %TYPE% $selfns $win $instance

                # Next, if this isn't a widget, delete the instance command.
                # If it is a widget, get the hull component's name, and rename
                # it back to the widget name
                
                # Next, delete the hull component's instance command,
                # if there is one.
                if {$Snit_isWidget} {
                    set hullcmd [Snit_component $selfns hull]
                
                    catch {rename $instance ""}

                    # Clear the bind event
                    bind Snit%TYPE%$win <Destroy> ""

                    if {[info command $hullcmd] != ""} {
                        rename $hullcmd ::$instance
                    }
                } else {
                    catch {rename $instance ""}
                }
            }

            # Next, delete the instance's namespace.  This kills any
            # instance variables.
            namespace delete $selfns
        }

        # Retrieves the object name given the component name.
        proc Snit_component {selfns name} {
            upvar ${selfns}::Snit_components Snit_components
            upvar ${selfns}::Snit_instance self

            if {![info exists Snit_components($name)]} {
                error "component '$name' is undefined in %TYPE% $self."
            }

            return $Snit_components($name)
        }

        #----------------------------------------------------------------
        # Compiled Procs
        #
        # These commands are created or replaced during compilation:

        # Snit_constructor type selfns win self args
        #
        # By default, just configures any passed options.  
        # Redefined by the "constructor" definition, hence always redefined
        # for widgets.
        proc Snit_constructor {type selfns win self args} { 
            $self configurelist $args
        }

        # Snit_instanceVars selfns
        #
        # Initializes the instance variables, if any.  Called during
        # instance creation.
        proc Snit_instanceVars {selfns} {
            %IVARDECS%
            %INSTANCEVARS%
        }

        # Snit_comptrace 
        #
        # Component trace; used for write trace on component instance 
        # variables.  Saves the new component object name, provided 
        # that certain conditions are met.
        proc Snit_comptrace {selfns component n1 n2 op} {
            typevariable Snit_isWidget
            upvar ${selfns}::${component} cvar
            upvar ${selfns}::Snit_components Snit_components

            # If they try to redefine the hull component after
            # it's been defined, that's an error--but only if
            # this is a widget or widget adaptor.
            if {"hull" == $component && 
                $Snit_isWidget &&
                [info exists ${selfns}::Snit_components($component)]} {
                set cvar $Snit_components($component)
                error "The hull component cannot be redefined."
            }

            # Save the new component value.
            set Snit_components($component) $cvar
        }

        # Snit_destructor type selfns win self
        #
        # Default destructor for the type.  By default, it does
        # nothing.  It's replaced by any user destructor.
        # For types, it's called by method destroy; for widgettypes,
        # it's called by a destroy event handler.
        proc Snit_destructor {type selfns win self} { }

        # Snit_configure<option> type selfns win self value
        #
        # Defined for each local option.  By default, just updates the
        # options array.  Redefined by an onconfigure definition.

        # Snit_cget<option> type selfns win self value
        #
        # Defined for each local option.  By default, just retrieves the
        # element from the options array.  Redefined by an oncget definition.

        # Snit_method<name> type selfns win self args...
        #
        # Defined for each local instance method.

        # Snit_typemethod<name> type args...
        #
        # Defined for each typemethod.

        #----------------------------------------------------------------
        # Snit variable management 

        # typevariable Declares that a variable is a static type variable.
        # It's equivalent to "::variable", operating in the %TYPE%
        # namespace.
        interp alias {} %TYPE%::typevariable {} ::variable

        # Declares an instance variable in a method or proc.  It's
        # only valid in instance code; it requires that selfns be defined.
        proc variable {varname} {
            upvar selfns selfns

            uplevel upvar ${selfns}::$varname $varname
        }

        # Returns the fully qualified name of a typevariable.
        proc typevarname {name} {
            return %TYPE%::$name
        }

        # Returns the fully qualified name of an instance variable.  
        # As with "variable", must be called in the context of a method.
        proc varname {name} {
            upvar selfns selfns
            return ${selfns}::$name
        }

        # Returns the fully qualified name of a proc (or typemethod).  
        # Unlike "variable", need not be called in the context of an
        # instance method.
        proc codename {name} {
            return %TYPE%::$name
        }

        # Use this like "list" to create a command string to pass to
        # another object (e.g., as a -command); it automatically inserts
        # the code at the beginning to call the right object, even if
        # the object's name has changed.  Requires that selfns be defined
        # in the calling context.
        proc mymethod {args} {
            upvar selfns selfns
            return [linsert $args 0 ::snit::CallInstance ${selfns}]
        }


        # Installs the named widget as the hull of a 
        # widgetadaptor.  Once the widget is hijacked, it's new name
        # is assigned to the hull component.
        #
        # TBD: This should only be public for widget adaptors.
        proc installhull {obj} {
            typevariable Snit_isWidget
            upvar self self
            upvar selfns selfns
            upvar ${selfns}::hull hull

            if {!$Snit_isWidget} { 
                error "installhull is valid only for snit::widgetadaptors"
            }
            
            if {[info exists ${selfns}::Snit_instance]} {
                error "hull already installed for %TYPE% $self"
            }

            if {![string equal $obj $self]} {
                error \
                    "hull name mismatch: '$obj' != '$self'"
            }

            set i 0
            while 1 {
                incr i
                set newName "::hull${i}$self"
                if {"" == [info commands $newName]} {
                    break
                }
            }

            rename ::$self $newName
            Snit_install $selfns $self

            # Note: this relies on Snit_comptrace to do the dirty work.
            set hull $newName

            return
        }

        # Looks for the named option in the named variable.  If found,
        # it and its value are removed from the list, and the value
        # is returned.  Otherwise, the default value is returned.
        # If the option is undelegated, it's own default value will be
        # used if none is specified.
        proc from {argvName option {defvalue ""}} {
            typevariable Snit_optiondefaults
            upvar $argvName argv

            set ioption [lsearch -exact $argv $option]

            if {$ioption == -1} {
                if {"" == $defvalue &&
                    [info exists Snit_optiondefaults($option)]} {
                    return $Snit_optiondefaults($option)
                } else {
                    return $defvalue
                }
            }

            set ivalue [expr {$ioption + 1}]
            set value [lindex $argv $ivalue]

            set argv [lreplace $argv $ioption $ivalue] 

            return $value
        }

        #----------------------------------------------------------------
        # Snit variables 

        # Array: General Snit Info
        #
        # ns:        The type's namespace
        # options:   List of the names of the type's local options.
        # counter:   Count of instances created so far.
        typevariable Snit_info
        set Snit_info(ns)      %TYPE%::
        set Snit_info(options) {}
        set Snit_info(counter) 0

        # Array: Public methods of this type.
        # Index is typemethod name; value is proc name.
        typevariable Snit_typemethods
        array unset Snit_typemethods

        # Array: Public methods of instances of this type.
        # The index is the method name.  For normal methods, 
        # the value is "".  For delegated methods, the value is
        # [list $component $command].
        typevariable Snit_methods
        array unset Snit_methods

        # Array: default option values
        #
        # $option          Default value for the option
        typevariable Snit_optiondefaults

        # Array: delegated option components
        #
        # $option          Component to which the option is delegated.
        typevariable Snit_delegatedoptions


        #----------------------------------------------------------
        # Type Command

        # Type dispatcher function.  Note: This function lives
        # in the parent of the %TYPE% namespace!  All accesses to 
        # %TYPE% variables and methods must be qualified!
        proc %TYPE% {method args} {
            global errorInfo

            # First, if the typemethod is unknown, we'll assume that it's
            # an instance name if we can.
            if {![info exists %TYPE%::Snit_typemethods($method)]} {
                if {[set %TYPE%::Snit_isWidget] && ![string match ".*" $method]} {
                    return -code error  "\"%TYPE% $method\" is not defined"
                }
                set args [concat $method $args]
                set method create
            }

            set procname [set %TYPE%::Snit_typemethods($method)]

            set errflag [catch {
                uplevel [concat %TYPE%::$procname %TYPE% $args]
            } result]

            if {$errflag} {
                return -code error -errorinfo $errorInfo $result
            } else {
                return $result
            }
        }

        #----------------------------------------------------------------
        # Dispatcher Command

        # Snit_install selfns instance
        #
        # Creates the instance proc, which calls the Snit_dispatcher.
        # "self" is the initial name of the instance, and "selfns" is
        # the instance namespace.
        proc Snit_install {selfns instance} {
            typevariable Snit_isWidget

            # FIRST, remember the instance name.  The Snit_instance variable
            # allows the instance to figure out its current name given the
            # instance namespace.
            upvar ${selfns}::Snit_instance Snit_instance
            set Snit_instance $instance

            # NEXT, qualify the proc name if it's a widget.
            if {$Snit_isWidget} {
                set procname ::$instance
            } else {
                set procname $instance
            }

            # NEXT, install the new proc
            proc $procname {method args} \
                "%TYPE%::Snit_dispatcher %TYPE% $selfns $instance \[set ${selfns}::Snit_instance] \$method \$args"

            # NEXT, add the trace.
            trace add command $procname {rename delete} \
                [list %TYPE%::Snit_tracer $selfns $instance]
        }

        # Snit_removetrace selfns instance
        proc Snit_removetrace {selfns win instance} {
            typevariable Snit_isWidget

            if {$Snit_isWidget} {
                set procname ::$instance
            } else {
                set procname $instance
            }

            # NEXT, remove any trace on this name
	    catch {
		trace remove command $procname {rename delete} \
			[list %TYPE%::Snit_tracer $selfns $win]
	    }
        }

        # Snit_tracer old new op
        #
        # This proc is called when the instance command is renamed.  old
        # is the old name, new is the new name, and op is rename or delete.
        # If op is delete, then new will always be "", so op is redundant.
        #
        # If the op is delete, we need to clean up the object; otherwise,
        # we need to track the change.
        #
        # NOTE: In Tcl 8.4.2 there's a bug: errors in rename and delete
        # traces aren't propagated correctly.  Instead, they silently
        # vanish.  Add a catch to output any error message.

        proc Snit_tracer {selfns win old new op} {
            typevariable Snit_isWidget

	    # Note to developers ...
	    # For Tcl 8.4.0, errors thrown in trace handlers vanish silently.
	    # Therefore we catch them here and create some output to help in
	    # debugging such problems.

            if {[catch {
                # FIRST, clean up if necessary
                if {"" == $new} {
                    if {$Snit_isWidget} {
                        destroy $win
                    } else {
                        Snit_cleanup $selfns $win
                    }
                } else {
                    # Otherwise, track the change.
                    upvar ${selfns}::Snit_instance Snit_instance
                    set Snit_instance [uplevel namespace which -command $new]
                }
            } result]} {
                global errorInfo
                # Pop up the console on Windows wish, to enable stdout.
		# This clobbers errorInfo unix, so save it.
		set ei $errorInfo
                catch {console show}
                puts "Error in Snit_tracer $selfns $win $old $new $op:"
                puts $ei
            }
        }

        # Calls a local method or a delegated method.
        #
        # type:		The instance's type
        # selfns:	The instance's private namespace
        # win:          The instance's original name (a Tk widget name, for
        #               snit::widgets.
        # self:         The instance's current name.
        # method:	The name of the method to call.
        # argList:      Arguments for the method.
        proc Snit_dispatcher {type selfns win self method argList} {
            global errorInfo

            typevariable Snit_methods
            upvar ${selfns}::Snit_components Snit_components
            
            if {![info exists Snit_methods($method)]} {
                if {![info exists Snit_methods(*)]} {
                    return -code error \
                        "'$self $method' is not defined."
                }
                set delegate [concat $Snit_methods(*) $method]
            } else {
                set delegate $Snit_methods($method)
            }

            if {[string length $delegate] == 0} {
                set command \
                    [list ${type}::Snit_method$method $type $selfns $win $self]
            } else {
                # Handle delegate
                set component [lindex $delegate 0]

                if {![info exists Snit_components($component)]} {
                    error "$type $self delegates '$method' to undefined component '$component'."
                }

                set comp $Snit_components($component)
                
                set command [lreplace $delegate 0 0 $comp]
            }

            set errflag [catch {
                uplevel 2 $command $argList
            } result]

            if {$errflag} {
		# Used to try to fix up "bad option", but did it badly.
                
                return -code error -errorinfo $errorInfo $result
            } else {
                return $result
            }
        }


        #----------------------------------------------------------
        # Compiled Definitions
            
        %COMPILEDDEFS%
    }
}

#-----------------------------------------------------------------------
# Snit Compilation Variables
#
# The following variables are used while Snit is compiling a type,
# and are disposed afterwards.

namespace eval ::snit:: {
    # The compile array accumulates information about the type or
    # widgettype being compiled.  It is cleared before and after each
    # compilation.  It has these indices:
    #
    # defs:              Compiled definitions, both standard and client.
    # instancevars:      Instance variable definitions and initializations.
    # ivprocdec:         Instance variable proc declarations.
    # tvprocdec:         Type variable proc declarations.
    # localoptions:      Names of local options.
    # delegatedoptions:  Names of delegated options.
    # localmethods:      Names of locally defined methods.
    # delegatedmethods:  Names of delegated methods.
    # components:        Names of defined components.
    variable compile

}

#-----------------------------------------------------------------------
# type compilation commands
#
# The type and widgettype commands use a slave interpreter to compile
# the type definition.  These are the procs
# that are aliased into it.

# Defines a constructor.
proc ::snit::Type.Constructor {type arglist body} {
    variable compile

    CheckArgs "constructor" $arglist

    # Next, add a magic reference to self.
    set arglist [concat type selfns win self $arglist]

    # Next, add variable declarations to body:
    set body "%TVARDECS%\n%IVARDECS%\n$body"

    append compile(defs) "proc Snit_constructor [list $arglist] [list $body]\n"
} 

# Defines a destructor.
proc ::snit::Type.Destructor {type body} {
    variable compile

    # Next, add variable declarations to body:
    set body "%TVARDECS%\n%IVARDECS%\n$body"

    append compile(defs) "proc Snit_destructor {type selfns win self} [list $body]"
} 

# Defines a type option.
proc ::snit::Type.Option {type option {defvalue ""}} {
    variable compile

    if {![string match {-*} $option]} {
        error "badly formed option '$option'"
    }

    if {[Contains $option $compile(delegatedoptions)]} {
        error "cannot delegate '$option'; it has been defined locally."
    }

    lappend compile(localoptions) $option

    set map [list %OPTION% $option %DEFVALUE% [list $defvalue]]
    
    append compile(defs) [string map $map {
        
        # Option $option
        lappend Snit_info(options) %OPTION%

        set Snit_optiondefaults(%OPTION%) %DEFVALUE%

        proc Snit_configure%OPTION% {type selfns win self value} {
            %TVARDECS%
            %IVARDECS%
            set options(%OPTION%) $value
        }

        proc Snit_cget%OPTION% {type selfns win self} {
            %TVARDECS%
            %IVARDECS%
            return $options(%OPTION%)
        }
    }]
}

# Defines an option's cget handler
proc ::snit::Type.Oncget {type option body} {
    variable compile

    if {[lsearch $compile(delegatedoptions) $option] != -1} {
        error "oncget $option: option '$option' is delegated."
    }

    if {[lsearch $compile(localoptions) $option] == -1} {
        error "oncget $option: option '$option' unknown."
    }

    # Next, add variable declarations to body:
    set body "%TVARDECS%\n%IVARDECS%\n$body"

    append compile(defs) [subst {

        proc Snit_cget$option {type selfns win self} [list $body]
    }]
} 

# Defines an option's configure handler.
proc ::snit::Type.Onconfigure {type option arglist body} {
    variable compile

    if {[lsearch $compile(delegatedoptions) $option] != -1} {
        error "onconfigure $option: option '$option' is delegated."
    }

    if {[lsearch $compile(localoptions) $option] == -1} {
        error "onconfigure $option: option '$option' unknown."
    }

    if {[llength $arglist] != 1} {
        error \
       "onconfigure $option handler should have one argument, got '$arglist'."
    }

    CheckArgs "onconfigure $option" $arglist

    # Next, add a magic reference to self and to options
    set arglist [concat type selfns win self $arglist]

    # Next, add variable declarations to body:
    set body "%TVARDECS%\n%IVARDECS%\n$body"

    append compile(defs) [subst {

        proc Snit_configure$option [list $arglist] [list $body]
    }]
} 

# Defines an instance method.
proc ::snit::Type.Method {type method arglist body} {
    variable compile

    if {[Contains $method $compile(delegatedmethods)]} {
        error "cannot delegate '$method'; it has been defined locally."
    }

    lappend compile(localmethods) $method

    CheckArgs "method $method" $arglist

    # Next, add magic references to type and self.
    set arglist [concat type selfns win self $arglist]

    # Next, add variable declarations to body:
    set body "%TVARDECS%\n%IVARDECS%\n$body"

    # Next, save the definition script.
    Mappend compile(defs) {

        # Method %METHOD% %ARGLIST%
        set Snit_methods(%METHOD%) ""

        proc Snit_method%METHOD% %ARGLIST% %BODY% 
    } %METHOD% $method %ARGLIST% [list $arglist] %BODY% [list $body] 
} 

# Defines a typemethod method.
proc ::snit::Type.Typemethod {type method arglist body} {
    variable compile

    CheckArgs "typemethod $method" $arglist

    # First, add magic reference to type.
    set arglist [concat type $arglist]

    # Next, add typevariable declarations to body:
    set body "%TVARDECS%\n$body"


    Mappend compile(defs) {

        # Typemethod %METHOD% %ARGLIST%
        set Snit_typemethods(%METHOD%) Snit_typemethod%METHOD%
        proc Snit_typemethod%METHOD% %ARGLIST% %BODY%
    } %METHOD% $method %ARGLIST% [list $arglist] %BODY% [list $body]
} 

# Defines a static proc in the type's namespace.
proc ::snit::Type.Proc {type proc arglist body} {
    variable compile

    # If "ns" is defined, the proc can see instance variables.
    if {[lsearch -exact $arglist selfns] != -1} {
        # Next, add instance variable declarations to body:
        set body "%IVARDECS%\n$body"
    }

    # The proc can always see typevariables.
    set body "%TVARDECS%\n$body"


    append compile(defs) [subst {

        # Proc $proc $arglist
        proc $proc [list $arglist] [list $body]
    }]
} 

# Defines a static variable in the type's namespace.
proc ::snit::Type.Typevariable {type name args} {
    variable compile

    if {[llength $args] > 1} {
        error "typevariable '$name' has too many initializers"
    }

    if {[llength $args] == 1} {
        append compile(defs) [subst {
            [list typevariable $name [lindex $args 0]]
        }]
    } else {
        append compile(defs) [subst {
            [list typevariable $name]
        }]
    }

    Mappend compile(tvprocdec) "upvar ${type}::${name} $name\n"
} 

# Defines an instance variable; the definition will go in the
# type's create typemethod.
proc ::snit::Type.Variable {type name args} {
    variable compile
    
    if {[llength $args] > 1} {
        error "variable '$name' has too many initializers"
    }

    if {[llength $args] == 1} {
        append compile(instancevars) [subst {
            [list set $name [lindex $args 0]]
        }]
    }

    Mappend compile(ivprocdec) {upvar ${selfns}::%N %N} \
        %N $name 
    append compile(ivprocdec) "\n"
} 

# Creates a delegated method or option, delegating it to a particular
# component and, optionally, to a particular option or method of that
# component.
#
# type          The type name
# which         method | option
# name          The name of the method or option, or * for all unknown
#               methods or options
# "to"          sugar; must be "to"
# component     The logical name of the delegate
# "as"          sugar; if not "", must be "as"
# thing         The name of the delegate's option, or the delegate's method,
#               possibly with arguments.  Must not be "" if "as" is "as";
#               ignored if "as" is ""

proc ::snit::Type.Delegate {
    type which name "to" component {"as" ""} {thing ""}
} {
    variable compile

    # FIRST, check syntax.
    if {![string equal $to "to"] ||
        (![string equal $as "as"] && ![string equal $as ""]) ||
        ([string equal $as "as"] && [string equal $thing ""]) ||
        ([string equal $name "*"] && ![string equal $thing ""])} {
        error "syntax error in definition: delegate $which $name..."
    }

    # NEXT, dispatch to method or option handler.
    switch $which {
        method {
            DelegatedMethod $type $name $component $thing
        }
        option {
            DelegatedOption $type $name $component $thing
        }
        default {
            error "syntax error in definition: delegate $which $name..."
        }
    }

    # NEXT, define the component
    DefineComponent $type $component
}

# Defines a name to be a component
# 
# The name becomes an instance variable; in addition, it gets a 
# write trace so that when it is set, all of the component mechanisms
# get updated.
#
# type          The type name
# component     The component name

proc ::snit::DefineComponent {type component} {
    variable compile

    if {[lsearch $compile(components) $component] == -1} {
        # Remember we've done this.
        lappend compile(components) $component

        # Make it an instance variable with no initial value
        Type.Variable $type $component ""

        # Add a write trace to do the component thing.
        Mappend compile(instancevars) {
            trace add variable %COMP% write \
                [list %TYPE%::Snit_comptrace $selfns %COMP%]
        } %TYPE% $type %COMP% $component
    }
} 

# Creates a delegated method delegating it to a particular
# component and, optionally, to a particular method of that
# component.
#
# type          The type name
# method        The name of the method
# component     The logical name of the delegate
# command       The name of the delegate's method, possibly with arguments,
#               or "".

proc ::snit::DelegatedMethod {type method component command} {
    variable compile

    if {![string equal $method "*"] &&
        [string equal $command ""]} {
        set command $method
    }

    if {[Contains $method $compile(localmethods)]} {
        error "cannot delegate '$method'; it has been defined locally."
    }

    if {![string equal $method "*"]} {
        lappend compile(delegatedmethods) $method
    }

    append compile(defs) [subst {
        # Delegated method $method to $component as $command
        [list set Snit_methods($method) [concat $component $command]]
    }]
} 

# Creates a delegated option, delegating it to a particular
# component and, optionally, to a particular option of that
# component.
#
# type          The type name
# option        The name of the option
# component     The logical name of the delegate
# target        The name of the delegate's option, or "".

proc ::snit::DelegatedOption {type option component target} {
    variable compile

    if {![string equal $option "*"] &&
        [string equal $target ""]} {
        set target $option
    }

    if {[Contains $option $compile(localoptions)]} {
        error "cannot delegate '$option'; it has been defined locally."
    }

    append compile(defs) [subst {
        # Delegated option $option to $component as $target
        [list set Snit_delegatedoptions($option) [list $component $target]]
    }]

    if {![string equal $option "*"]} {
        lappend compile(delegatedoptions) $option
        append compile(defs) [subst {
            # Delegated option $option to $component as $target
            [list set Snit_delegatedoptions($option) [list $component $target]]
        }]
    }
} 

#-----------------------------------------------------------------------
# Public commands

proc ::snit::type {type body} {
    return [Define type $type $body]
}

proc ::snit::widgetadaptor {type body} {
    return [Define widgetadaptor $type $body]
}

proc ::snit::widget {type body} {
    return [Define widget $type $body]
}


#-----------------------------------------------------------------------
# Definition commands

proc ::snit::Define {which type body} {
    variable typeTemplate
    variable defs
    variable compile

    # FIRST, qualify the name.
    if {![string match "::*" $type]} {
        # Get caller's namespace; 
        # append :: if not global namespace.
        set ns [uplevel 2 namespace current]
        if {"::" != $ns} {
            append ns "::"
        }
        
        set type "$ns$type"
    }

    # NEXT, initialize the class data
    set compile(defs) {}
    set compile(localoptions) {}
    set compile(instancevars) {}
    set compile(delegatedoptions) {}
    set compile(ivprocdec) {}
    set compile(tvprocdec) {}
    set compile(localmethods) {}
    set compile(delegatedmethods) {}
    set compile(components) {}

    append compile(defs) \
        "typevariable Snit_isWidget [string match widget* $which]\n\n"
    append compile(defs) \
    "typevariable Snit_isWidgetAdaptor [string match widgetadaptor $which]\n\n"

    if {"widgetadaptor" == $which} {
        # A widgetadaptor is also a widget.
        set which widget
    }

    # NEXT, create the class interpreter
    if {![string length [info command class.interp]]} {
        interp create class.interp
	class.interp eval {catch {package require snit::__does_not_exist__}}
    }
    class.interp alias constructor  ::snit::Type.Constructor  $type
    class.interp alias destructor   ::snit::Type.Destructor   $type
    class.interp alias option       ::snit::Type.Option       $type
    class.interp alias onconfigure  ::snit::Type.Onconfigure  $type
    class.interp alias oncget       ::snit::Type.Oncget       $type
    class.interp alias typemethod   ::snit::Type.Typemethod   $type
    class.interp alias method       ::snit::Type.Method       $type
    class.interp alias proc         ::snit::Type.Proc         $type
    class.interp alias typevariable ::snit::Type.Typevariable $type
    class.interp alias variable     ::snit::Type.Variable     $type
    class.interp alias delegate     ::snit::Type.Delegate     $type

    # NEXT, Add the standard definitions; then 
    # evaluate the type's definition in the class interpreter.
    class.interp eval [Expand $defs(common) %TYPE% $type]
    class.interp eval [Expand $defs($which) %TYPE% $type]
    class.interp eval $body

    # NEXT, if this is a widget define the hull component if it isn't
    # already defined.
    if {"widget" == $which} {
        DefineComponent $type hull
    }

    # NEXT, substitute the compiled definition into the type template
    # to get the type definition script.
    set defscript [Expand $typeTemplate \
                       %COMPILEDDEFS% $compile(defs)]

    # NEXT, substitute the defined macros into the type definition script.
    # This is done as a separate step so that the compile(defs) can 
    # contain the macros defined below.
    set defscript [Expand $defscript \
                       %TYPE%         $type \
                       %IVARDECS%     $compile(ivprocdec) \
                       %TVARDECS%     $compile(tvprocdec) \
                       %INSTANCEVARS% $compile(instancevars)]

    array unset compile

    # NEXT, execute the type definition script.

    #puts "#----\nnamespace eval $type\{$defscript\n\}\n#-----"
    if {[catch {namespace eval $type $defscript} result]} {
        namespace delete $type
        error $result
    }

    return $type
}


#-----------------------------------------------------------------------
# Instance introspection commands

# Returns the instance's type.
proc ::snit::InstanceInfo_type {type selfns win self} {
    return $type
}

# Returns the instance's type's typevariables
proc ::snit::InstanceInfo_typevars {type selfns win self} {
    return [TypeInfo_typevars $type]
}

# Returns the instance's instance variables
proc ::snit::InstanceInfo_vars {type selfns win self} {
    set result {}
    foreach name [info vars ${selfns}::*] {
        set tail [namespace tail $name]
        if {![string match "Snit_*" $tail]} {
            lappend result $name
        }
    }

    return $result
}

# Returns a list of the names of the instance's options
proc ::snit::InstanceInfo_options {type selfns win self} {
    upvar ${type}::Snit_optiondefaults Snit_optiondefaults
    upvar ${type}::Snit_delegatedoptions Snit_delegatedoptions

    set result {}

    # First, get the local options
    foreach name [array names Snit_optiondefaults] {
        lappend result $name
    }

    # Next, get the delegated options.  Check and see if unknown 
    # options are delegated.
    set gotStar 0
    foreach name [array names Snit_delegatedoptions] {
        if {"*" == $name} {
            set gotStar 1
        } else {
            lappend result $name
        }
    }

    # If "configure" works as for Tk widgets, add the resulting
    # options to the list.
    if {$gotStar} {
        upvar ${selfns}::Snit_components Snit_components
        set logicalName [lindex $Snit_delegatedoptions(*) 0]
        set comp $Snit_components($logicalName)

        if {![catch {$comp configure} records]} {
            foreach record $records {
                set opt [lindex $record 0]
                if {[lsearch -exact $result $opt] == -1} {
                    lappend result $opt
                }
            }
        }
    }

    return $result
}

#-----------------------------------------------------------------------
# Type introspection commands

# Returns the instance's type's typevariables
proc ::snit::TypeInfo_typevars {type} {
    set result {}
    foreach name [info vars ${type}::*] {
        set tail [namespace tail $name]
        if {![string match "Snit_*" $tail]} {
            lappend result $name
        }
    }
    
    return $result
}

# Returns the instance's instance variables
proc ::snit::TypeInfo_instances {type} {
    upvar ${type}::Snit_isWidget Snit_isWidget
    set result {}

    foreach selfns [namespace children $type] {
        upvar ${selfns}::Snit_instance instance

        lappend result $instance
    }

    return $result
}


#-----------------------------------------------------------------------
# Utility Functions

# Builds a template from a tagged list of text blocks, then substitutes
# all symbols in the mapTable, returning the expanded template.
proc ::snit::Expand {template args} {
    return [string map $args $template]
}

# Expands a template and appends it to a variable.
proc ::snit::Mappend {varname template args} {
    upvar $varname myvar

    append myvar [string map $args $template]
}

# Return a unique command name.  
#
# Require: type is a fully qualified name.
# Require: name contains "%AUTO%"
proc ::snit::UniqueName {countervar type name} {
    upvar $countervar counter 
    while 1 {
        # FIRST, bump the counter and define the %AUTO% instance name;
        # then substitute it into the specified name.
        incr counter
        set auto "[namespace tail $type]$counter"
        set candidate [snit::Expand $name %AUTO% $auto]
        if {[info commands $candidate] == ""} {
            return $candidate
        }
    }
}

# Return a unique instance namespace
proc ::snit::UniqueInstanceNamespace {countervar type} {
    upvar $countervar counter 
    while 1 {
        # FIRST, bump the counter and define the namespace name.
        # Then see if it already exists.
        incr counter
        set ins "${type}::Snit_inst${counter}"
        if {![namespace exists $ins]} {
            return $ins
        }
    }
}

# Checks argument list against reserved args 
proc ::snit::CheckArgs {which arglist} {
    variable reservedArgs
    
    foreach name $reservedArgs {
        if {[Contains $name $arglist]} {
            error "$which's arglist may not contain '$name' explicitly."
        }
    }
}

# Returns 1 if a value is in a list, and 0 otherwise.
proc ::snit::Contains {value list} {
    if {[lsearch -exact $list $value] != -1} {
        return 1
    } else {
        return 0
    }
}

proc ::snit::CallInstance {selfns args} {
    upvar ${selfns}::Snit_instance self
    return [uplevel 1 [linsert $args 0 $self]]
}