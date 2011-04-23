/*
 * Copyright (C) 2010 Collabora Ltd.
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors:
 *       Philip Withnall <philip.withnall@collabora.co.uk>
 */

using GLib;
using Gee;

/* We have to declare our own wrapping of g_log so that it doesn't have the
 * [Diagnostics] attribute, which would cause valac to add the Vala source file
 * name to the message format, which we don't want. This is used in
 * Debug.print_line(). */
[PrintfFormat]
private extern void g_log (string? log_domain,
    LogLevelFlags log_level,
    string format,
    ...);

/**
 * Manage debug output and status reporting for all folks objects. All GLib
 * debug logging calls are passed through a log handler in this class, which
 * allows debug domains to be outputted according to whether they've been
 * enabled by being passed to {@link Debug.dup}.
 *
 * @since UNRELEASED
 */
public class Folks.Debug : Object
{
  private enum Domains {
    /* Zero is used for "no debug spew" */
    CORE = 1 << 0,
    TELEPATHY_BACKEND = 1 << 1,
    KEY_FILE_BACKEND = 1 << 2
  }

  private static weak Debug _instance; /* needs to be locked when accessed */
  private HashSet<string> _domains; /* needs to be locked when accessed */
  private bool _all = false; /* needs _domains to be locked when accessed */

  /* The current indentation level, in spaces */
  private uint _indentation = 0;
  private string _indentation_string = "";

  private bool _colour_enabled = true;

  /*
   * Whether colour output is enabled. If true, debug output may include
   * terminal colour escape codes. Disabled by the environment variable
   * FOLKS_DEBUG_NO_COLOUR being set to anything except “0”.
   *
   * This property is thread-safe.
   *
   * @since UNRELEASED
   */
  public bool colour_enabled
    {
      get
        {
          lock (this._colour_enabled)
            {
              return this._colour_enabled;
            }
        }

      set
        {
          lock (this._colour_enabled)
            {
              this._colour_enabled = value;
            }
        }
    }

  private bool _debug_output_enabled = true;

  /**
   * Whether debug output is enabled. This is orthogonal to the set of enabled
   * debug domains; filtering of debug output as a whole is done after filtering
   * by enabled domains.
   *
   * @since UNRELEASED
   */
  public bool debug_output_enabled
    {
      get
        {
          lock (this._debug_output_enabled)
            {
              return this._debug_output_enabled;
            }
        }

      set
        {
          lock (this._debug_output_enabled)
            {
              this._debug_output_enabled = value;
            }
        }
    }

  /**
   * Signal emitted in the main thread whenever objects should print their
   * current status. All significant objects in the library should connect
   * to this and print their current status in some suitable format when it's
   * emitted.
   *
   * Client processes should emit this signal by calling
   * {@link Debug.emit_print_status}.
   *
   * @since UNRELEASED
   */
  public signal void print_status ();

  /**
   * Log domain for the status messages logged as a result of calling
   * {@link Debug.emit_print_status().
   *
   * This could be used in conjunction with a log handler to redirect the
   * status information to a debug window or log file, for example.
   *
   * @since UNRELEASED
   */
  public const string STATUS_LOG_DOMAIN = "folks-status";

  private void _print_status_log_handler_cb (string? log_domain,
      LogLevelFlags log_levels,
      string message)
    {
      /* Print directly to stdout without any adornments */
      GLib.stdout.printf ("%s\n", message);
    }

  private void _log_handler_cb (string? log_domain,
      LogLevelFlags log_levels,
      string message)
    {
      if (this.debug_output_enabled == false)
        {
          /* Don't output anything if debug output is disabled, even for
           * enabled debug domains. */
          return;
        }

      /* Otherwise, pass through to the default log handler */
      Log.default_handler (log_domain, log_levels, message);
    }

  /* turn off debug output for the given domain unless it was in the FOLKS_DEBUG
   * environment variable (or 'all' was set) */
  internal void _register_domain (string domain)
    {
      lock (this._domains)
        {
          if (this._all || this._domains.contains (domain.down ()))
            {
              Log.set_handler (domain, LogLevelFlags.LEVEL_MASK,
                  this._log_handler_cb);
              return;
            }
        }

      /* Install a log handler which will blackhole the log message.
       * Other log messages will be printed out by the default log handler. */
      Log.set_handler (domain, LogLevelFlags.LEVEL_DEBUG,
          (domain_arg, flags, message) => {});
    }

  /**
   * Create or return the singleton {@link Debug} class instance.
   * If the instance doesn't exist already, it will be created with no debug
   * domains enabled.
   *
   * This function is thread-safe.
   *
   * @return		Singleton {@link Debug} instance
   * @since UNRELEASED
   */
  public static Debug dup ()
    {
      lock (Debug._instance)
        {
          var retval = Debug._instance;

          if (retval == null)
            {
              /* use an intermediate variable to force a strong reference */
              retval = new Debug ();
              Debug._instance = retval;
            }

          return retval;
        }
    }

  /**
   * Create or return the singleton {@link Debug} class instance.
   * If the instance doesn't exist already, it will be created with the given
   * set of debug domains enabled. Otherwise, the existing instance will have
   * its set of enabled domains changed to the provided set.
   *
   * @param debug_flags		A comma-separated list of debug domains to
   *				enable, or null to disable debug output
   * @param colour_enabled	Whether debug output should be coloured using
   *				terminal escape sequences
   * @return			Singleton {@link Debug} instance
   * @since UNRELEASED
   */
  public static Debug dup_with_flags (string? debug_flags,
      bool colour_enabled)
    {
      var retval = Debug.dup ();

      lock (retval._domains)
        {
          retval._all = false;
          retval._domains = new HashSet<string> (str_hash, str_equal);

          if (debug_flags != null && debug_flags != "")
            {
              var domains_split = debug_flags.split (",");
              foreach (var domain in domains_split)
                {
                  var domain_lower = domain.down ();

                  if (GLib.strcmp (domain_lower, "all") == 0)
                    retval._all = true;
                  else
                    retval._domains.add (domain_lower);
                }
            }
        }

      retval.colour_enabled = colour_enabled;

      return retval;
    }

  private Debug ()
    {
      /* Private constructor for singleton */

      /* Install a log handler for log messages emitted as a result of
       * Debug.print-status being emitted. */
      Log.set_handler (Debug.STATUS_LOG_DOMAIN, LogLevelFlags.LEVEL_MASK,
          this._print_status_log_handler_cb);
    }

  ~Debug ()
    {
      /* Manually clear the singleton _instance */
      lock (Debug._instance)
        {
          Debug._instance = null;
        }
    }

  /**
   * Causes all significant objects in the library to print their current
   * status to standard output, obeying the options set on this
   * {@link Debug} instance for colouring and other formatting.
   *
   * @since UNRELEASED
   */
  public void emit_print_status ()
    {
      print ("Dumping status information…\n");
      this.print_status ();
    }

  /**
   * Increment the indentation level used when printing output through the
   * object.
   *
   * This is intended to be used by backend libraries only.
   *
   * @since UNRELEASED
   */
  public void indent ()
    {
      /* We indent in increments of two spaces */
      this._indentation++;
      this._indentation_string = string.nfill (this._indentation * 2, ' ');
    }

  /**
   * Decrement the indentation level used when printing output through the
   * object.
   *
   * This is intended to be used by backend libraries only.
   *
   * @since UNRELEASED
   */
  public void unindent ()
    {
      this._indentation--;
      this._indentation_string = string.nfill (this._indentation * 2, ' ');
    }

  /**
   * Print a debug line with the current indentation level for the specified
   * debug domain.
   *
   * This is intended to be used by backend libraries only.
   *
   * @param domain	The debug domain name
   * @param level	A set of log level flags for the message
   * @param format	A printf-style format string for the heading
   * @param ...		Arguments for the format string
   * @since UNRELEASED
   */
  [PrintfFormat ()]
  public void print_line (string domain,
      LogLevelFlags level,
      string format,
      ...)
    {
      /* FIXME: store the va_list temporarily to work around bgo#638308 */
      var valist = va_list ();
      string output = format.vprintf (valist);
      g_log (domain, level, "%s%s", this._indentation_string, output);
    }

  /**
   * Print a debug line as a heading. It will be coloured according to the
   * current indentation level so that different levels of headings stand out.
   *
   * This is intended to be used by backend libraries only.
   *
   * @param domain	The debug domain name
   * @param level	A set of log level flags for the message
   * @param format	A printf-style format string for the heading
   * @param ...		Arguments for the format string
   * @since UNRELEASED
   */
  [PrintfFormat ()]
  public void print_heading (string domain,
      LogLevelFlags level,
      string format,
      ...)
    {
      /* Colour the heading according to the current indentation level.
       * ANSI terminal colour codes. */
      const int[] heading_colours =
        {
          31, /* red */
          32, /* green */
          34 /* blue */
        };

      var wrapper_format = "%s";
      if (this.colour_enabled == true)
        {
          var indentation =
              this._indentation.clamp (0, heading_colours.length - 1);
          wrapper_format =
              "\033[1;%im%%s\033[0m".printf (heading_colours[indentation]);
        }

      /* FIXME: store the va_list temporarily to work around bgo#638308 */
      var valist = va_list ();
      string output = format.vprintf (valist);
      this.print_line (domain, level, wrapper_format, output);
    }

  /*
   * Format a potentially null string for printing; if the string is null,
   * “(null)” will be outputted. If coloured output is enabled, this output
   * will be coloured brown. */
  private string _format_nullable_string (string? input)
    {
      if (this.colour_enabled == true && input == null)
        {
          return "\033[1;36m(null)\033[0m"; /* cyan */
        }
      else if (input == null)
        {
          return "(null)";
        }

      return input;
    }

  struct KeyValuePair
    {
      string key;
      string? val;
    }

  /**
   * Print a set of key–value pairs in a table. The width of the key column is
   * automatically set to the width of the longest key. The keys and values
   * must be provided as a null-delimited list of alternating key–value varargs.
   * Values may be null but keys may not.
   *
   * This is intended to be used by backend libraries only.
   *
   * The table will be printed at the current indentation level plus one.
   *
   * @param domain	The debug domain name
   * @param level	A set of log level flags for the message
   * @param ...		Alternating keys and values, terminated with null
   * @since UNRELEASED
   */
  public void print_key_value_pairs (string domain,
      LogLevelFlags level,
      ...)
    {
      var valist = va_list ();
      KeyValuePair[] lines = {};
      uint max_key_length = 0;

      /* Read in the arguments and calculate the longest key for alignment
       * purposes */
      while (true)
        {
          string? key = valist.arg ();
          if (key == null)
            {
              break;
            }

          string? val = valist.arg ();

          /* Keep track of the longest key we've seen */
          max_key_length = uint.max (key.length, max_key_length);

          lines += KeyValuePair ()
            {
              key = key,
              val = val
            };
        }

      this.indent ();

      /* Print out the lines */
      foreach (var line in lines)
        {
          var padding = string.nfill (max_key_length - line.key.length, ' ');
          this.print_line (domain, level, "%s: %s%s", line.key, padding,
              this._format_nullable_string (line.val));
        }

      this.unindent ();
    }
}
