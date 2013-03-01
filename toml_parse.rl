#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <time.h>

#include "toml.h"
#include <signal.h>

struct toml_stack_item {
	struct list_node list;
	enum toml_type list_type;
	struct toml_node *node;
};

static const char *
toml_type_to_str(enum toml_type type)
{
#define CASE_ENUM_TO_STR(x) case(x): return #x
	switch (type) {
	CASE_ENUM_TO_STR(TOML_ROOT);
	CASE_ENUM_TO_STR(TOML_KEYGROUP);
	CASE_ENUM_TO_STR(TOML_LIST);
	CASE_ENUM_TO_STR(TOML_INT);
	CASE_ENUM_TO_STR(TOML_FLOAT);
	CASE_ENUM_TO_STR(TOML_STRING);
	CASE_ENUM_TO_STR(TOML_DATE);
	}
#undef CASE_ENUM_TO_STR
	return "unknown toml type";
}

%%{
	machine toml;

	whitespace = [\t ]*;

	name = (print - (whitespace|']'))+ >{ts = p;};

	action float_add_place {
		floating += (fc - '0') * ((float)1/dec_pos);
		dec_pos *= 10;
	}

	action saw_key {
		name = strndup(ts, namelen);
	}

	action saw_int {
		number *= sign;

		struct toml_stack_item *cur_list =
						list_tail(&list_stack, struct toml_stack_item, list);

		if (cur_list) {
			if (cur_list->list_type && cur_list->list_type != TOML_INT) {
				fprintf(stderr, "incompatible types list %s this %s line %d\n",
						toml_type_to_str(cur_list->list_type),
						toml_type_to_str(TOML_INT), curline);
				parse_error = 1;
				fbreak;
			}
			cur_list->list_type = TOML_INT;

			struct toml_list_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			item->node.type = TOML_INT;
			item->node.value.integer = number;
			item->node.name = NULL;

			list_add_tail(&cur_list->node->value.list, &item->list);
		} else {
			struct toml_keygroup_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			item->node.name = name;
			item->node.type = TOML_INT;
			item->node.value.integer = number;

			list_add_tail(&cur_keygroup->value.map, &item->map);
		}

		fhold;
	}

	action saw_float {
		floating *= sign;

		struct toml_stack_item *cur_list =
						list_tail(&list_stack, struct toml_stack_item, list);

		if (cur_list) {
			if (cur_list->list_type && cur_list->list_type != TOML_FLOAT) {
				fprintf(stderr, "incompatible types list %s this %s line %d\n",
						toml_type_to_str(cur_list->list_type),
						toml_type_to_str(TOML_FLOAT), curline);
				parse_error = 1;
				fbreak;
			}
			cur_list->list_type = TOML_FLOAT;

			struct toml_list_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			item->node.type = TOML_FLOAT;
			item->node.value.floating = floating;
			item->node.name = NULL;

			list_add_tail(&cur_list->node->value.list, &item->list);
		} else {
			struct toml_keygroup_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			list_add_tail(&cur_keygroup->value.map, &item->map);
			item->node.name = name;
			item->node.type = TOML_FLOAT;
			item->node.value.floating = floating;
		}

		fhold;
	}

	action saw_string {
		int len = strp - string;
		*strp = 0;

		struct toml_stack_item *cur_list =
						list_tail(&list_stack, struct toml_stack_item, list);

		if (cur_list) {
			if (cur_list->list_type && cur_list->list_type != TOML_STRING) {
				fprintf(stderr, "incompatible types list %s this %s line %d\n",
						toml_type_to_str(cur_list->list_type),
						toml_type_to_str(TOML_STRING), curline);
				parse_error = 1;
				fbreak;
			}
			cur_list->list_type = TOML_STRING;

			struct toml_list_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			item->node.type = TOML_STRING;
			item->node.value.string = malloc(len);
			if (!item->node.value.string) {
				malloc_error = 1;
				fbreak;
			}
			memcpy(item->node.value.string, string, len);
			item->node.name = NULL;

			list_add_tail(&cur_list->node->value.list, &item->list);
		} else {
			struct toml_keygroup_item *item = malloc(sizeof(*item));

			list_add_tail(&cur_keygroup->value.map, &item->map);
			item->node.name = name;
			item->node.type = TOML_STRING;
			item->node.value.string = malloc(len);
			if (!item->node.value.string) {
				malloc_error = 1;
				fbreak;
			}
			memcpy(item->node.value.string, string, len);
		}
	}

	action saw_date {
		struct toml_stack_item *cur_list =
						list_tail(&list_stack, struct toml_stack_item, list);

		if (cur_list) {
			if (cur_list->list_type && cur_list->list_type != TOML_DATE) {
				fprintf(stderr, "incompatible types list %s this %s line %d\n",
						toml_type_to_str(cur_list->list_type),
						toml_type_to_str(TOML_DATE), curline);
				parse_error = 1;
				fbreak;
			}
			cur_list->list_type = TOML_DATE;

			struct toml_list_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			item->node.type = TOML_DATE;
			item->node.value.epoch = timegm(&tm);
			item->node.name = NULL;

			list_add_tail(&cur_list->node->value.list, &item->list);
		} else {
			struct toml_keygroup_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			list_add_tail(&cur_keygroup->value.map, &item->map);
			item->node.name = name;
			item->node.type = TOML_DATE;
			item->node.value.epoch = timegm(&tm);
		}
	}

	action start_list {
		struct toml_node *node;

		/*
		 * if the list stack is empty add this list to the keygroup
		 * otherwise it should be added the to list on top of the stack
		 */
		if (list_empty(&list_stack)) {
			struct toml_keygroup_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			/* first add it to the keygroup */
			item->node.type = TOML_LIST;
			list_head_init(&item->node.value.list);
			list_add_tail(&cur_keygroup->value.map, &item->map);
			item->node.name = name;
			node = &item->node;
		} else {
			struct toml_stack_item *tail =
						list_tail(&list_stack, struct toml_stack_item, list);

			struct toml_list_item *item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}

			item->node.type = TOML_LIST;
			item->node.name = NULL;
			list_head_init(&item->node.value.list);

			list_add_tail(&tail->node->value.list, &item->list);
			node = &item->node;
		}

		/* push this list onto the stack */
		struct toml_stack_item *stack_item = malloc(sizeof(*stack_item));
		if (!stack_item) {
			malloc_error = 1;
			fbreak;
		}
		stack_item->node = node;
		stack_item->list_type = 0;
		list_add_tail(&list_stack, &stack_item->list);
	}

	action end_list {
		struct toml_stack_item *tail =
						list_tail(&list_stack, struct toml_stack_item, list);

		list_del(&tail->list);
		free(tail);
	}

	action saw_keygroup {
		char *ancestor, *tofree, *keygroupname;

		struct toml_node *place = toml_root;

		tofree = keygroupname = strndup(ts, (int)(p-ts));

		while ((ancestor = strsep(&keygroupname, "."))) {
			struct toml_keygroup_item *item;
			int found = 0;

			list_for_each(&place->value.map, item, map) {
				if (strcmp(item->node.name, ancestor) == 0) {
					place = &item->node;
					found = 1;
					break;
				}
			}

			if (found)
				continue;

			/* this is the auto-vivification */
			item = malloc(sizeof(*item));
			if (!item) {
				malloc_error = 1;
				fbreak;
			}
			item->node.name = strdup(ancestor);
			item->node.type = TOML_KEYGROUP;
			list_head_init(&item->node.value.map);
			list_add_tail(&place->value.map, &item->map);

			place = &item->node;
		}

		free(tofree);

		if (place->type != TOML_KEYGROUP) {
			parse_error = 1;
			fbreak;
		}

		cur_keygroup = place;
	}

	lines = (
		start: (
			# count the indentation to know where the keygroups end
			[\t ]* >{ indent = 0; } ${ indent++; } ->text
		),

		# just discard everything until newline
		comment: ( [^\n]*[\n] @{curline++;} ->start ),

		# a keygroup
		keygroup: ( name ']' @saw_keygroup ->start ),

		# the boolean data type
		true: 	( any	>{fhold;}	->start ),
		false: 	( any 	>{fhold;}	->start ),

		# String, we have to escape \0, \t, \n, \r, everything else can
		# be prefixed with a slash and the slash just gets dropped
		string: (
			'"'  $saw_string					->start			|
			[\n]    ${curline++; *strp++=fc;}	->string		|
			[\\]								->str_escape	|
			[^"\n\\]	${*strp++=fc;}				->string
		),
		str_escape: (
			"0"	${*strp++=0;}		-> string |
			"t"	${*strp++='\t';}	-> string |
			"n"	${*strp++='\n';}	-> string |
			"r"	${*strp++='\r';}	-> string |
			[^0tnr]	${*strp++=fc;}	-> string
		),

		# A sign can optiionally prefix a number
		sign: (
			'-' ${sign = -1;}	->number |
			'+' ${sign = 1;}	->number
		),
		number: (
			digit ${number *= 10; number += fc - '0';}	->number			|
			'.'	${floating = number; dec_pos = 10;}		->fractional_part	|
			[\n] ${curline++;} $saw_int					->start				|
			[^0-9.]	$saw_int							->start
		),


		# When we don't know yet if this is going to be a date or a number
		# this is the state
		number_or_date: (
			digit ${number *= 10; number += fc - '0';}	->number_or_date	|
			'-'	${tm.tm_year = number - 1900;}			->date				|
			'.'	${floating = number * sign; dec_pos = 10;}			->fractional_part	|
			[\n] ${curline++;} $saw_int								->start	|
			[\t ,\]] $saw_int										->start
		),


		# Fractional part of a double
		fractional_part: (
			[0-9] 	$float_add_place	->fractional_part |
			[^0-9]  $saw_float			->start
		),

		# Zulu date, we've already picked up the first four digits and the '-'
		# when figuring this was a date and not a number
		date: (
			digit{2} @{tm.tm_mon = atoi(fpc-1) - 1;}
			'-'
			digit{2} @{tm.tm_mday = atoi(fpc-1);}
			'T'
			digit{2} @{tm.tm_hour = atoi(fpc-1);}
			':'
			digit{2} @{tm.tm_min = atoi(fpc-1);}
			':'
			digit{2} @{tm.tm_sec = atoi(fpc-1);}
			'Z' @saw_date ->start
		),

		# Non-list value
		singular: (
			'true'								-> true		|
			'false'								-> false	|
			'"' ${strp = string;}				-> string	|
			('-'|'+') ${fhold;number = 0;}		-> sign		|
			digit ${sign = 1;fhold;number = 0;}	-> number_or_date
		),

		# A list of values
		list: (
			'#'								->comment	|
			'\n' ${ curline++; }			->list		|
			[\t ]							->list		|
			']'	$end_list					->start		|
			[^#\t \n\]]	${fhold;}			->val
		),

		# A val can be either a list or a singular value
		val: (
			'#'							->comment	|
			'\n' ${ curline++; }		->val		|
			[\t ]						->val		|
			'[' $start_list				->list		|
			']'	$end_list				->start		|
			[^#\t \n[\]] ${fhold;}		->singular
		)

		# A regular key
		key: (
			name  whitespace >{namelen = (int)(p-ts);} '=' $saw_key ->val
		),

		# Text stripped of leading whitespace
		text: (
			'#'							->comment	|
			'['							->keygroup	|
			[\t ]						->text		|
			'\n' ${curline++;}			->start     |
			','							->val		|
			']' $end_list				->start		|
			[^#[\t \n,\]]	${fhold;}	->key
		)
	);

	main := lines?;
}%%

%%write data;

int
toml_parse(struct toml_node *toml_root, char *buf, int buflen)
{
	int indent = 0, cs, curline = 1;
	char *p, *pe;
	char *ts;
	char string[1024], *strp;
	int sign, number, dec_pos, namelen;
	struct tm tm;
	double floating;
	char *name;
	int parse_error = 0, malloc_error = 0;

	struct toml_node *cur_keygroup = toml_root;

	struct list_head list_stack;
	list_head_init(&list_stack);

	assert(toml_root->type == TOML_ROOT);

	%% write init;

	p = buf;
	pe = buf + buflen;

	%% write exec;

	if (malloc_error) {
		fprintf(stderr, "malloc failed, line %d\n", curline);
		return 1;
	}

	if (cs == toml_error || parse_error) {
		fprintf(stderr, "PARSE_ERROR, line %d, p = '%.5s'", curline, p);
		return 1;
	}

	return 0;
}
